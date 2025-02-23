use v5.36;

package PAUSEx::Log;

use warnings;
no warnings;

use Mojo::Util qw(dumper);
use Carp qw(croak);
use Digest::SHA1;

our $VERSION = '0.002';

sub DESTROY {}

sub AUTOLOAD {
	our $AUTOLOAD;
	my $method = $AUTOLOAD =~ s/.*:://r;

	my( $self , @rest ) = @_;
	croak "Method <$method> not found" unless $self->can($method);

	use experimental qw(builtin);
	my $class = builtin::blessed($self);

	no strict 'refs';
	*{"${class}::$method"} = sub { return $_[0]->{$method} };
	goto &{"${class}::$method"};
	}

=encoding utf8

=head1 NAME

PAUSEx::Log - Access the PAUSE log

=head1 SYNOPSIS

	use v5.36;
	use PAUSEx::Log;

	my $start = time;

	FETCH: while( 1 ) {
		last if time - $start > 10 * 60;

		my $entries = PAUSEx::Log->fetch_log();

		MESSAGE: foreach my $entry ( $entries->@* ) {
			next unless $entry->for_pause_id( 'BRIANDFOY' );
			say $entry->message;
			last FETCH if ...
			}

		sleep 5*60;
		}

=head1 DESCRIPTION

The Perl Authors Upload Server provides a tail of its log file so
module authors can check the progress of their modules through the
PAUSE process. This might take several minutes from the time of upload,
and I want to monitor the log until I know my latest release has been
seen by PAUSE.

This module fetches that log and digests it in various ways.

=head1 Class methods

=over 4

=item fetch_log( PAUSE_USER, PAUSE_PASS )

Fetch the PAUSE log, using your PAUSE ID and password. You can also
set these in the C<CPAN_PASS> and C<CPAN_PASS> environment variables, which
this function will automatically pick up.

=cut

sub fetch_log ( $class, $user = $ENV{CPAN_USER}, $pass = $ENV{CPAN_PASS} ) {
	state $rc = require Mojo::UserAgent;
	state $ua = Mojo::UserAgent->new;
	state $url_template = 'https://%s:%s@pause.perl.org/pause/authenquery?ACTION=tail_logfile&pause99_tail_logfile_1=5000&pause99_tail_logfile_sub=Tail+characters';
	state $url = sprintf $url_template, $user, $pass;

	my $tx = $ua->get( $url );

	my $entries = $tx->res->dom
		->find( 'div#logs table.table tbody.list tr td.log' )
		->map( 'text' )
		->map( sub { PAUSEx::Log->_parse_log_line($_) } )
		;
	}


=back

=head2 Instance methods

=over 4

=item can( METHOD )

Returns true if the message contains that information since different
types of message have different things they record. For example,
not all messages contain the PAUSE ID

	if( $entry->can('pause_id') ) { ... }

=cut

sub can ($either, $method) {
	state $class_methods = {
		map { $_, 1 } qw(_new can _parse_log_line _parse_message)
		};
	state $common_methods = {
		map { $_, 1 } qw(date time huh version level message id type)
		};

	if( ref $either ) {
		my $instance = { map { $_, 1 } $either->names };
		return 1 if(
			exists $common_methods->{$method} or exists $instance->{$method}
			);
		}
	else {
		return 1 if exists $class_methods->{$method};
		}
	}

=item categories

Returns a list of namespaces that represent log message types, such
as C<PAUSEx::Log::Line::get>.

=cut

sub categories {
	my $c = [ map { 'PAUSEx::Log::Line::' . $_ } qw(
		entered
		enqueue
		fetch
		get
		mldistwatch_start
		reaped
		received
		renamed
		verified
		unknown
		)
		];

	wantarray ? @$c : $c
	}

=back

=cut

sub _parse_log_line ($class, $log_line) {
	my( $date, $time, $pid, $paused, $level, $message )
		= split /\s+/, $log_line, 6;

	$pid =~ s/\D//g;

	$paused =~ s/:\z//;
	$level =~ s/:\z//; $level = lc($level);

	my $paused_line;
	if( $paused =~ /paused:(\d+)/ ) {
		$paused_line = $1;
		}

	my %hash = (
		date         => $date,
		time         => $time,
		pid          => $pid,
		level        => $level,
		paused_line  => $paused_line,
		message      => $message,
		id           => Digest::SHA1::sha1_hex($message),
		raw          => $log_line,
		);

	PAUSEx::Log->_parse_message(\%hash),
	}

sub _parse_message ( $class, $hash ) {
	local $_ = $hash->{message};

	do {
		state $uri_re = qr| (?<full_path>
			(?<base_path> .+                )? /?
			(?<first>                [A-Z]  ) /
			(?<second>    \g{first}  [A-Z]  ) /
			(?<pause_id>  \g{second} [A-Z]+ ) /
			(?<distname>  [^/]+             )
			)
			|x;
		state $dt = qr/\A\d\d:\d\d:\d\d\.\d{4}/a;

		if( /\ANeed to get uriid\[$uri_re\]/ ) {
			PAUSEx::Log::Line::enqueue->new( $hash, @+{qw(full_path pause_id distname)} );
			}
		elsif( /\AGoing to fetch uriid\[$uri_re\]/ ) {
			PAUSEx::Log::Line::fetch->new( $hash, @+{qw(full_path pause_id distname)} );
			}
		elsif( /\ARequesting a GET on uri \[(.+)\]/ ) {
			PAUSEx::Log::Line::get->new( $hash, $1 );
			}
		elsif( /\Arenamed '(.+?)' to '$uri_re'/ ) {
			PAUSEx::Log::Line::renamed->new( $hash, $1, @+{qw(full_path pause_id distname)} );
			}
		elsif( /\AGot $uri_re \(size (?<size>\d+)\)/ ) {
			PAUSEx::Log::Line::received->new( $hash, @+{qw(full_path pause_id distname size)} );
			}
		elsif( /\ASent 'has entered' email about uriid\[$uri_re\]/ ) {
			PAUSEx::Log::Line::entered->new( $hash, @+{qw(full_path pause_id distname)} );
			}
		elsif( /\AVerified $uri_re/ ) {
			PAUSEx::Log::Line::verified->new( $hash, @+{qw(full_path pause_id distname)} );
			}
		elsif( /\AStarted mldistwatch for lpath\[$uri_re\] with pid\[(?<pid>\d+)\]/ ) {
			PAUSEx::Log::Line::mldistwatch_start->new( $hash, @+{qw(full_path pause_id distname pid)} );
			}
		elsif( /\AReaped child\[(\d+)\]/ ) {
			PAUSEx::Log::Line::reaped->new( $hash, $1 );
			}
		else {
			PAUSEx::Log::unknown->_new( $hash );
			}
		};
	}


=head2 Log line type

Each log line is parsed and assigned a category, where that category
can be a catch-all "unknown" category. The result of C<fetch_log> (as
in the L</SYNOPSIS>) is a list of log line objects. These objects
share some common methods, then have additional methods as appropriate.

=head3 Log line methods

=over 4

=item date

(Common) The date of the log line, in YYYY-MM-DD

=item distname

The distribution name (Foo-Bar-1.23.tgz), if the message refers to one.

=item for_pause_id( PAUSE_ID )

Returns true if the log message is about PAUSE_ID.

	foreach my $entry ( fetch()->@* ) {
		next unless $entry->for_pause_id( 'BRIANDFOY' );
		...
		}

=item id

(Common) A made up unique ID for the log message so you can tell if you've
seen that log line before.

=item is_enqueue

=item is_entered

=item is_fetch

=item is_get

=item is_mldistwatch_start

=item is_reaped

=item is_renamed

=item is_received

=item is_verified

These return true if the log message could be classified as one of
these types, and false otherwise. This happens through crude pattern
matching.

=item is_unknown

Returns true is the message could not be classified, and false
otherwise. This is the default type.

=item level

(Common) The log level

=item message

(Common) The log message

=item pause_id

The PAUSE ID of the message, if the message refers to one

=item time

(Common) The time of the log entry

=item type

(Common) The type of message

=cut

BEGIN {
package PAUSEx::Log::Line {
    use Carp qw(croak);

	sub new ( $class, $hash, @values ) {
		my @names = $class->names;
		if( @names != @values ) {
			croak "Names mismatch for: $hash->{message}\n  (@names) <- (@values)"
			}

		$hash->@{@names} = @values;

		bless $hash, $class;
		}

	sub pause_id { () }

	sub for_pause_id ( $self, $pause_id ) {
		return unless defined $pause_id;
		return unless $self->can('pause_id');
		return $self->pause_id eq uc $pause_id;
		}

	sub is_enqueue           { 0 }
	sub is_entered           { 0 }
	sub is_fetch             { 0 }
	sub is_get               { 0 }
	sub is_mldistwatch_start { 0 }
	sub is_reaped            { 0 }
	sub is_renamed           { 0 }
	sub is_received          { 0 }
	sub is_verified          { 0 }
	sub is_unknown           { 1 }

	sub type ( $self ) {
		use experimental(qw(builtin));
		builtin::blessed($self) =~ s/.*:://r;
		}

	}

package PAUSEx::Log::Line::entered           { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_entered { 1 }           sub names { qw(uri_id pause_id distname) }      }
package PAUSEx::Log::Line::enqueue           { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_enqueue { 1 }           sub names { qw(uri_id pause_id distname) }      }
package PAUSEx::Log::Line::fetch             { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_fetch { 1 }             sub names { qw(uri_id pause_id distname) }      }
package PAUSEx::Log::Line::get               { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_get { 1 }               sub names { qw(uri) }                           }
package PAUSEx::Log::Line::mldistwatch_start { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_mldistwatch_start { 1 } sub names { qw(lpath pause_id distname pid) }   }
package PAUSEx::Log::Line::reaped            { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_reaped { 1 }            sub names { qw(pid) }                           }
package PAUSEx::Log::Line::received          { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_received { 1 }          sub names { qw(uri_id pause_id distname size) } }
package PAUSEx::Log::Line::renamed           { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_renamed { 1 }           sub names { qw(tmp dest pause_id distname) }    }
package PAUSEx::Log::Line::verified          { our @ISA = qw(PAUSEx::Log::Line); sub is_unknown { 0 } sub is_verified { 1 }          sub names { qw(uri_id pause_id distname) }      }
package PAUSEx::Log::Line::unknown           { our @ISA = qw(PAUSEx::Log::Line); sub names { qw() } }
}


=back

=head1 TO DO


=head1 SEE ALSO


=head1 SOURCE AVAILABILITY

This source is in Github:

	http://github.com/briandfoy/pausex-log

=head1 AUTHOR

brian d foy, C<< <briandfoy@pobox.com> >>

=head1 COPYRIGHT AND LICENSE

Copyright © 2023-2025, brian d foy, All Rights Reserved.

You may redistribute this under the terms of the Artistic License 2.0.

=cut

1;
