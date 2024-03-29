use ExtUtils::MakeMaker;

$|=0;

my %config;

while($_ = shift) {
    my ($key, $val) = split(/=/, $_, 2);
    $config{$key} = $val;
}

my $DEBUG = delete $config{DEBUG};

require XML::GDOME;
if ($XML::GDOME::VERSION < 0.75) {
    die "XML::GDOME 0.75 or higher required\n";
}

# get libs and inc from gnome-config
eval {
    print "running xslt-config... ";
    my $ver = backtick('xslt-config --version');
    my ($major, $minor, $point) = $ver =~ /(\d+)\.(\d+)\.(\d+)/g;
    die "VERSION" unless $major > 1 || $minor > 0 || $point >= 6;
    $config{LIBS} ||= backtick('xslt-config --libs');
    $config{INC} ||= backtick('xslt-config --cflags');
    $config{LIBS} .= ' ' . backtick('gdome-config --libs');
    $config{INC} .= ' ' . backtick('gdome-config --cflags');
    print "ok\n";
};
if ($@) {
    print "failed\n";
    if ($@ =~ /^VERSION/) { 
        die "XML::GDOME::XSLT needs libxslt version 1.0.6 or higher\n";
    }
    warn "*** ", $@ if $DEBUG;
    warn "using fallback values for LIBS and INC\n";
    # backtick fails if gnome-config didn't exist...
    $config{LIBS} = '-L/usr/local/lib -L/usr/lib -lxslt -lxml2 -lgdome -lz -lm -glib';
    $config{INC} = '-I/usr/local/include/libgdome -I/usr/local/include -I/usr/include';
    
    print <<OPT;
options:
  LIBS='$config{LIBS}'
  INC='$config{INC}'
If this is wrong, Re-run as:
  \$ $^X Makefile.PL LIBS='-L/path/to/lib' INC='-I/path/to/include'

OPT

}

if ($config{LIBS} !~ /\-lxslt/) {
    $config{LIBS} .= ' -lxslt -lxml2 -lz -lm';
}

if (!have_library("xslt")) {
    die <<DEATH;
libxslt not found
Try setting LIBS and INC values on the command line
Or get libxslt and libxml2 from 
  http://www.libxml.org/
If you install via RPMs, make sure you also install the -devel
RPMs, as this is where the headers (.h files) are.
DEATH
}

if (have_library("exslt")) {
    $config{LIBS} =~ s/-lxslt/-lxslt -lexslt/;
    $config{DEFINE} .= " -DHAVE_EXSLT"
}

WriteMakefile(
    'NAME'	=> 'XML::GDOME::XSLT',
    'VERSION_FROM' => 'XSLT.pm', # finds $VERSION
    'AUTHOR'    => 'T.J. Mather',
    'ABSTRACT'  => 'Interface to Gnome libxslt library',
    'PREREQ_PM' => { 'XML::GDOME' => "0.75", },
    %config,
);

###################################################################
# Functions
#  - these should really be in MakeMaker... But &shrug;
###################################################################

use Config;
use Cwd;
use Symbol;
use File::Spec;

use vars qw/$DEVNULL $is_Win32/;

BEGIN {
    $is_Win32 = ($^O =~ /Win32/);
    if ($is_Win32) {
        $DEVNULL = 'DEVNULL';
    }
    else {
        $DEVNULL = eval { File::Spec->devnull };
        if ($@) { $DEVNULL = '/dev/null' }
    }
}

sub rm_f {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    if (@realfiles) {
        chmod(0777, @realfiles);
        unlink(@realfiles);
    }
}

sub rm_fr {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    foreach my $file (@realfiles) {
        if (-d $file) {
            # warn("$file is a directory\n");
            rm_fr("$file/*");
            rm_fr("$file/.exists");
            rmdir($file) || die "Couldn't remove $file: $!";
        }
        else {
            # warn("removing $file\n");
            chmod(0777, $file);
            unlink($file);
        }
    }
}

sub xsystem {
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        if (system($command) != 0) {
            die "system call to '$command' failed";
        }
        return 1;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $retval = system($command);
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "system call to '$command' failed";
    }
    return 1;
}

sub backtick {
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        my $results = `$command`;
        chomp $results;
        if ($? != 0) {
            die "backticks call to '$command' failed";
        }
        return $results;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $results = `$command`;
    my $retval = $?;
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "backticks call to '$command' failed";
    }
    chomp $results;
    return $results;
}

sub try_link0 {
    my ($src, $opt) = @_;
    my $cfile = gensym();
    # local $config{LIBS};
    # $config{LIBS} .= $opt;
    unless (mkdir(".testlink", 0777)) {
        rm_fr(".testlink");
        mkdir(".testlink", 0777) || die "Cannot create .testlink dir: $!";
    }
    chdir(".testlink");
    open($cfile, ">Conftest.xs") || die "Cannot write to file Conftest.xs: $!";
print $cfile <<EOT;
#ifdef __cplusplus
extern "C" {
#endif
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#ifdef __cplusplus
}
#endif

EOT
    print $cfile $src;
    print $cfile <<EOT;

MODULE = Conftest          PACKAGE = Conftest

PROTOTYPES: DISABLE

EOT
    close($cfile);
    open($cfile, ">Conftest.pm") || die "Cannot write to file Conftest.pm: $!";
    print $cfile <<'EOT';
package Conftest;
$VERSION = 1.0;
require DynaLoader;
@ISA = ('DynaLoader');
bootstrap Conftest $VERSION;
1;
EOT
    close($cfile);
    open($cfile, ">Makefile.PL") || die "Cannot write to file Makefile.PL: $!";
    print $cfile <<'EOT';
use ExtUtils::MakeMaker;
my %config;
while($_ = shift @ARGV) {
    my ($k, $v) = split /=/, $_, 2;
    warn("$k = $v\n");
    $config{$k} = $v;
}
WriteMakefile(NAME => "Conftest", VERSION_FROM => "Conftest.pm", %config);
EOT
    close($cfile);
    open($cfile, ">test.pl") || die "Cannot write to file test.pl: $!";
    print $cfile <<EOT;
use Test; BEGIN { plan tests => 1; } END { ok(\$loaded) }
use Conftest; \$loaded++;
EOT
    close($cfile);
    xsystem("$^X Makefile.PL " . join(' ', map { "'$_=$config{$_}'" } keys %config));
    xsystem("$Config{make} test 'OTHERLDFLAGS=$opt'");
}

sub try_link {
    my $start_dir = cwd();
    my $result = eval {
        try_link0(@_);
    };
    warn $@ if $DEBUG && $@;
    chdir($start_dir);
    rm_fr(".testlink");
    return $result;
}

sub have_library {
    my ($lib, $func) = (@_, "blank");
    printf("checking for %s() in -l%s... ", $func, $lib) if $func ne "blank";
    printf("looking for -l%s... ", $lib) if $func eq "blank";

    my $result;
    if ($func) {
        my $libs = $is_Win32 ? " $lib.lib  " : "-l$lib";
        if ($is_Win32) {
            $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
blank() { return 0; }
int t() { ${func}(); return 0; }
SRC
            unless ($result) {
                $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
blank() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))${func}; return 0; }
SRC
            }
        }
        else {

            $result = try_link(<<"SRC", $libs);
blank() { return 0; }
int t() { ${func}(); return 0; }
SRC
        }
    }

    unless ($result) {
        print "no\n";
        return 0;
    }

    if ($func ne "main") {
        $config{DEFINE} .= uc(" -Dhave_$func");
    }

    print "yes\n";
    return 1;
}
