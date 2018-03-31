package File::ContentStore;

use 5.014;

use Carp qw( croak );
use Types::Standard qw( slurpy Object Str ArrayRef );
use Types::Path::Tiny qw( Dir File );
use Type::Params qw( compile );
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
    isa     => Str,
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
    state $check = compile( Object, File );
    my ( $self, $file ) = $check->(@_);

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

sub link_dir {
    state $check = compile( Object, slurpy ArrayRef[Dir] );
    my ( $self, $dirs ) = $check->(@_);

    $_->visit( sub { $self->link_file($_) }, { recurse => 1 } )
      for @$dirs;
}

1;
