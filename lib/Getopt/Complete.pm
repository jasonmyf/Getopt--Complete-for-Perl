
use strict;
use warnings;

package Getopt::Complete;

use version;
our $VERSION = qv(0.02);

use Getopt::Long;

our %handlers;

our @OPT_SPEC;
our $OPTS_OK;
our %OPTS;

sub import {    
    my $class = shift;
    
    # parse out the options spec at the end of each key, if present
    # prepare the specification for GetOptions
    # normalize...
    %handlers = (@_);
    my $bare_args = 0;
    for my $key (sort keys %handlers) {
        my ($name,$spec) = ($key =~ /^([\w|\-]\w+|\<\>)(.*)/);
        if (not defined $name) {
            print STDERR __PACKAGE__ . " is unable to parse $key! from spec!";
            next;
        }
        $handlers{$name} = delete $handlers{$key};
        if ($name eq '<>') {
            $bare_args = 1;
            next;
        }
        $spec ||= '=s';
        push @OPT_SPEC, $name . $spec;
    }

    if ($ENV{COMP_LINE}) {
        # This command has been set to autocomplete via "complete -F".
        # More info about the command linie iis available than with -C.
        # SUPPORT IS INCOMPLETE FOR THIS WAY OF AUTO-COMPLETING!

        my $left = substr($ENV{COMP_LINE},0,$ENV{COMP_POINT});
        my $current = '';
        if ($left =~ /([^\=\s]+)$/) {
            $current = $1;
            $left = substr($left,0,length($left)-length($current));
        }
        $left =~ s/\s+$//;

        my @other_options = split(/\s+/,$left);
        my $command = $other_options[0];
        my $previous = pop @other_options if $other_options[-1] =~ /^--/;
        @ARGV = @other_options;
        $Getopt::Complete::OPTS_OK = Getopt::Long::GetOptions(\%OPTS,@OPT_SPEC);
        @Getopt::Complete::ERRORS = invalid_options();
        $Getopt::Complete::OPTS_OK = 0 if $Getopt::Complete::ERRORS;
        Getopt::Complete::print_matches_and_exit($command,$current,$previous,\@other_options);
    }
    elsif (my $shell = $ENV{GETOPT_COMPLETE}) {
        # This command has been set to autocomplete via "complete -C".
        # This is easiest to set-up, but less info about the command-line is present.
        if ($shell eq 'bash') {
            my ($command, $current, $previous) = (map { defined $_ ? $_ : '' } @ARGV);
            $previous = '' unless $previous =~ /^-/; 
            Getopt::Complete::print_matches_and_exit($command,$current,$previous);
        }
        else {
            print STDERR "\ncommand-line completion: unsupported shell $shell\n";
            print " \n";
            exit;
        }
    }
    else {
        # Normal execution of the program (or else an error in use of "complete" to tell bash about this program.)
        do {
            my @orig_argv = @ARGV;
            local $SIG{__WARN__} = sub { push @Getopt::Complete::ERRORS, @_ };
            $Getopt::Complete::OPTS_OK = Getopt::Long::GetOptions(\%OPTS,@OPT_SPEC);
            if (@ARGV) {
                if ($bare_args) {
                    my $a = $Getopt::Complete::OPTS{'<>'} ||= [];
                    push @$a, @ARGV;
                }
                else {
                    print STDERR "xa @ARGV\n";
                    $Getopt::Complete::OPTS_OK = 0;
                    for my $arg (@ARGV) {
                        push @Getopt::Complete::ERRORS, "unexpected unnamed arguments: $arg";
                    }
                }
            }
            @ARGV = @orig_argv;
        };
        if (my @more_errors = invalid_options()) {
            #warn "value errors " . scalar(@more_errors);
            #use Data::Dumper;
            #print STDERR Dumper(\@more_errors);
            $Getopt::Complete::OPTS_OK = 0;
            push @Getopt::Complete::ERRORS, @more_errors;
        }
    }
}

sub invalid_options {
    my @failed;
    for my $key (sort keys %handlers) {
        my $completions = $handlers{$key};
        
        next if ($key eq '<>');
        my ($dashes,$name,$spec) = ($key =~ /^(\-*)(\w+)(.*)/);
        if (not defined $name) {
            print STDERR "key $key is unparsable in " . __PACKAGE__ . " spec inside of $0 !!!";
            next;
        }

        my @values = (ref($OPTS{$name}) ? @{ $OPTS{$name} } : $OPTS{$name});
        for my $value (@values) {
            next if not defined $value;
            if (ref($completions) eq 'CODE') {
                $completions = $completions->($value,$key);
                $completions = [] if not defined $completions;
            }
            if (not defined $completions) {
                next;
            }
            elsif (ref($completions) eq 'ARRAY') {
                unless (grep { $_ eq $value } @$completions) {
                    my $msg = (($key || 'arguments') . " has invalid value $value");
                    push @failed, $msg;
                }
            }
            elsif ($value ne $completions) {
                my $msg = (($key || 'arguments') . " has invalid value $value");
                push @failed, $msg;
                last;
            }
        }
    }
    return @failed;
}

sub print_matches_and_exit {
    my ($command, $current, $previous, $all) = @_;
    no warnings;
    #print STDERR "recvd: " . join(',',@_) . "\n";
    #print "11 22 33\n";
    #exit;
 
    my @args = keys %handlers;
    my @possibilities;

    my ($dashes,$resolve_values_for_option_name) = ($previous =~ /^(--)(.*)/); 
    
    if (not length $previous) {
        # an unqalified argument, or an option name
        if ($current =~ /^(-+)/) {
            # the incomplete word is an option name
            @possibilities = map { '--' . $_ } grep { $_ ne '<>' } @args;
        }
        else {
            # bare argument
            $resolve_values_for_option_name = '<>';
        }
    }

    if ($resolve_values_for_option_name) {
        # either a value for a named option, or a bare argument.
        if (my $handler = $handlers{$resolve_values_for_option_name}) {
            # the incomplete word is a value for some option (possible the option '<>' for bare args)
            if (defined($handler) and not ref($handler) eq 'ARRAY') {
                $handler = $handler->($command,$current,$previous,$all);
            }
            unless (ref($handler) eq 'ARRAY') {
                die "values for $previous must be an arrayref! got $handler\n";
            }
            @possibilities = @$handler;
        }
        else {
            # no possibilities
            # print STDERR "recvd: " . join(',',@_) . "\n";
            @possibilities = ();
        }
    }

    my @matches; 
    for my $p (@possibilities) {
        my $i =index($p,$current);
        if ($i == 0) {
            push @matches, $p; 
        }
    }

    print join("\n",@matches),"\n";
    exit;
}

# Manufacture the long and short sub-names on the fly.

for my $subname (qw/
    files
    directories
    commands
    users
    groups
    environment
    services
    aliases
    builtins
/) {
    my $option = substr($subname,0,1);
    my $code = sub {
        [ grep { $_ !~/^\s+$/ } `bash -c 'compgen -$option'` ], 
    };
    no strict 'refs';
    *$subname = $code;
    *$option = $code;
}

sub update_bashrc {
    use File::Basename;
    use IO::File;
    my $me = basename($0);

    my $found = 0;
    my $added = 0;
    if ($ENV{GETOPT_COMPLETE_APPS}) {
        my @apps = split('\s+',$ENV{GETOPT_COMPLETE_APPS});
        for my $app (@apps) {
            if ($app eq $me) {
                # already in the list
                return;
            }
        }
    }

    # we're not on the list: try to update .bashrc
    my $bashrc = "$ENV{HOME}/.bashrc";
    if (-e $bashrc) {
        my $bashrc_fh = IO::File->new($bashrc);
        unless ($bashrc_fh) {
            die "Failed to open $bashrc to add tab-completion for $me!\n";
        } 
        my @lines = $bashrc_fh->getlines();
        $bashrc_fh->close;
        
        for my $line (@lines) {
            if ($line =~ /^\s*export GETOPT_COMPLETE_APPS=/) {
                if (index($line,$me) == -1) {
                    $line =~ s/\"\s*$//;
                    $line .= ' ' . $me . '"' .  "\n";
                    $added++;
                }
                else {
                    $found++;
                }
            }
        }

        if ($added) {
            # append to the existing apps variable
            $bashrc_fh = IO::File->new(">$bashrc");
            unless ($bashrc_fh) {
                die "Failed to open $bashrc to add tab-completion for $me!\n";
            }
            $bashrc_fh->print(@lines);
            $bashrc_fh->close;
            return 1;
        }

        if ($found) {
            print STDERR "WARNING: Run this now to activate tab-completion: source ~/.bashrc\n";
            print STDERR "WARNING: This will occur automatically for subsequent logins.\n";
            return;
        }
    }

    # append a block of logic to the bashrc
    my $bash_src = <<EOS;
    # Added by the Getopt::Complete Perl module
    export GETOPT_COMPLETE_APPS="\$GETOPT_COMPLETE_APPS $me"
    for app in \$GETOPT_COMPLETE_APPS; do
        complete -C GETOPT_COMPLETE=bash\\ \$app \$app
    done
EOS
    my $bashrc_fh = IO::File->new(">>$bashrc");
    unless ($bashrc_fh) {
        die "Failed to open .bashrc: $!\n";
    }
    while ($bash_src =~ s/^ {4}//m) {}
    $bashrc_fh->print($bash_src);
    $bashrc_fh->close;

    return 1;
}

# At exit, ensure that command-completion is configured in bashrc for bash users.
# It's easier to do for the user than explain.

END {
    # DISABLED!
    if (0 and $ENV{SHELL} =~ /\wbash$/) {
        if (eval { update_bashrc() }) {
            print STDERR "WARNING: Added command-line tab-completion to $ENV{HOME}/.bashrc.\n";
            print STDERR "WARNING: Run this now to activate tab-completion: source ~/.bashrc\n";
            print STDERR "WARNING: This will occur automatically for subsequent logins.\n";
        }
        if ($@) {
            warn "WARNING: failed to extend .bashrc to handle tab-completion! $@";
        }
    }
}

1;

=pod 

=head1 NAME

Getopt::Complete - add custom dynamic bash autocompletion to Perl applications

=head1 SYNOPSIS

In the Perl program "myprogram":

  use Getopt::Complete
      '--frog'    => ['ribbit','urp','ugh'],
      '--fraggle' => sub { return ['rock','roll'] },
      '--person'  => \&Getopt::Complete::users, 
      '--output'  => \&Getopt::Complete::files, 
      '--exec'    => \&Getopt::Complete::commands, 
      ''          => \&Getopt::Complete::environment, 
  ;

In ~/.bashrc or ~/.bash_profile, or directly in bash:

  complete -C 'GETOPT_COMPLETE=bash myprogram1' myprogram
  
Thereafter in the terminal (after next login, or sourcing the .bashrc):

  $ myprogram --f<TAB>
  $ myprogram --fr

  $ myprogram --fr<TAB><TAB>
  frog fraggle

  $ myprogram --fro<TAB>
  $ myprogram --frog 

  $ myprogram --frog <TAB>
  ribbit urp ugh

  $ myprogram --frog r<TAB>
  $ myprogram --frog ribbit

=head1 DESCRIPTION

Perl applications using the Getopt::Complete module can "self serve"
as their own shell-completion utility.

When "use Getopt::Complete" is encountered at compile time, the application
will detect that it is being run by bash (or bash-compatible shell) to do 
shell completion, and will respond to bash instead of running the app.

When running the program in "completion mode", bash will comminicate
the state of the command-line using environment variables and command-line
parameters.  The app will exit after sending a response to bash.  As
such the application should "use Getopt::Complete" before doing other
processing, and before parsing/modifying the enviroment or @ARGV. 

=head1 BACKGROUND ON BASH COMPLETION

The bash shell supports smart completion of words when the TAB key is pressed.

By default, bash will presume the word the user is typing is a file name, 
and will attempt to complete the word accordingly.  Bash can, however, be
told to run a specific program to handle the completion task.  The "complete" 
command instructs the shell as-to how to handle tab-completion for a given 
command.  

This module allows a program to be its own word-completer.  It detects
that the GETOPT_COMPLETE environment variable is set to the name of
some shell (currenly only bash is supported), and responds by
returning completion values suitable for that shell _instead_ of really 
running the application.

The "use"  statement for the module takes a list of key-value pairs 
to control the process.  The format is described below.

=head1 KEYS

Each key in the list decribes an option which can be completed.

=over 4

=item plain text

A normal word is interpreted as an option name.  Dashes are optional.
Getopt-style suffixes are ignored as well.

=item a blank string ('')

A blank key specifiies how to complete non-option (bare) arguments.

=back

=head1 VALUES

Each value describes how that option should be completed.

=over 4

=item array reference 

An array reference expliciitly lists the valid values for the option.

=item undef 

An undefined value indicates that the  option has no following value (for boolean flags)

=item subroutine reference 

This will be called, and expected to return an array of possiible matches.

=item plain text

A text string will be presumed to be a subroutine name, which will be called as above.

=back

There is a built-in subroutine which provides access to compgen, the bash built-in
which does completion on file names, command names, users, groups, services, and more.

See USING BUILTIN COMPLETIONS below.

=head1 USING SUBROUTINE CALLBACKS

A subroutine callback will always receieve two arguments:

=over 4

=item current word

This is the word the user is trying to complete.  It may be an empty string, if the user hits <Tab>
without typiing anything first.

=item previous option

This is the option argument to the left of the word the user is typing.  If the word to the left 
is not an option argument, or there is no word to the left besidies the command itself, this 
will be an empty string.

=back

In cases where bash launches the app with the -F option, two additional values 
are available.  See below (COMPLETIONS WHICH REQUIRE EXAMINING THE ENTIRE COMMAND LINE)
for details:

=over 4

=item argv 

An arrayref containing all of @ARGV _except_ the key/value pair being resolved.
This is useful when one option's value controls what values are valid for other options.

=item opts

A hashref made from processing the above incomplete ARGV. 

=back

The return value is a list of possible matches.  The callback is free to narrow its results
by examining the current word, but is not required to do so.  The module will always return
only the appropriate matches.

=head1 USING BUILTIN COMPLETIONS

Any of the default shell completions supported by bash's compgen are supported by this module.
The full name is alissed as the single-character compgen parameter name for convenience.

See "man bash", in the Programmable Complete secion for more details.

=head1 COMPLETIONS WHICH REQUIRE EXAMINING THE ENTIRE COMMAND LINE 

In some cases, the options which should be available change depending on what other
options are present, or the values available change depending on other options or their
values.

The standard "complete -C" does not supply the entire command-line to the completion
program, unfortunately.  Getopt::Complete, as of version v0.02, now recognizes when
bash is configured to call it with "complete -F".  Using this involves adding a
few more lines of code to your .bashrc or .bash_profile:

  _getopt_complete() {
      export COMP_LINE COMP_POINT;
      COMPREPLY=( $( ${COMP_WORDS[0]} ) )
  }

The "complete" command then can look like this in the .bashrc/.bash_profile: 

  complete -F _getopt_complete myprogram

This has the same effect as the simple "complete -C" entry point, except that
all callbacks which are subroutines will received two additional parameters:
1. the remaining parameters as an arrayref
2. the above already processed through GetOpt::Long into a hashref.


  use Getopt::Complete
    type => ['names','places'],
    instance => sub {
            my ($value, $key, $argv, $opts) = @_;
            if ($opts{type} eq 'names') {
                return [qw/larry moe curly/],
            }
            elsif ($opts{type} eq 'places') {
                return [qw/here there everywhere/],
            }
        }

=head1 BUGS

Currently only supports bash, though other shells could be added easily.

Imperfect handling of cases where the value in a key-value starts with a dash.

There is logic in development to have the tool possibly auto-update the user's .bashrc / .bash_profile, but this
is still in development.

=head1 AUTHOR

Scott Smith <sakoht aht seepan>

=cut

