package File::ContentStore;

use Carp qw( croak );
use Types::Path::Tiny qw( Dir File );
use Digest;

use Moo;
use namespace::clean;

has path => (
    is       => 'ro',
    isa      => Dir,
    required => 1,
    coerce   => 1,
);

has digest => (
    is      => 'ro',
    default => 'SHA-1',
);

has parts => (
    is => 'lazy',
    builder =>
      sub { int( length( Digest->new( shift->digest )->hexdigest ) / 32 ) },
    init_arg => undef,
);

my $BUFF_SIZE = 1024 * 32;
my $DIGEST_OPTS = { chunk_size => $BUFF_SIZE };

sub link_file {
    my ($self, $file) = @_;
    $file = Path::Tiny->new($file);

    # compute content file name
    my $digest = $file->digest( $DIGEST_OPTS, $self->digest );
    my $content =
      $self->path->child(
        map( { substr $digest, 2 * $_, 2 } 0 .. $self->parts - 1 ),
        substr( $digest, 2 * $self->parts ) );
    $content->parent->mkpath;

    # link both files
    my ( $old, $new ) = -e $content ? ( $content, $file ) : ( $file, $content );

    return if $old eq $new;    # do not link a file to itself
    unlink $new if -e $new;
    link $old, $new or croak "Failed linking $new to to $old: $!";
    chmod 0444, $old;

    return $content;
}

1;
