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

# if a single non-hashref argument is given, assume it's 'path'
sub BUILDARGS {
    my $class = shift;
    scalar @_ == 1
      ? ref $_[0] eq 'HASH'
          ? { %{ $_[0] } }
          : { path => $_[0] }
      : @_ % 2 ? Carp::croak(
            "The new() method for $class expects a hash reference or a"
          . " key/value list. You passed an odd number of arguments" )
      : {@_};
}

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

    # check for collisions
    if( -e $content ) {
        croak "Collision found for $file and $content: size differs"
           if -s $file != -s $content;

        my @buf;
        my @fh = map $_->openr_raw, $file, $content;
        while( $fh[0]->sysread( $buf[0], $BUFF_SIZE ) ) {
            $fh[1]->sysread( $buf[1], $BUFF_SIZE );
            croak "Collision found for $file and $content: content differs"
                 if $buf[0] ne $buf[1];
        }
    }

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

    $_->visit( sub { $self->link_file($_) if -f }, { recurse => 1 } )
      for @$dirs;
}

sub fsck {
    my ($self) = @_;
    $self->path->visit(
        sub {
            my ( $path, $state ) = @_;

            if ( -d $path ) {

                # empty directory
                push @{ $state->{empty} }, $path unless $path->children;
            }
            else {

                # orphan content file
                push @{ $state->{orphan} }, $path
                  if $path->stat->nlink == 1;

                # content does not match name
                my $digest = $path->digest( $DIGEST_OPTS, $self->digest );
                push @{ $state->{corrupted} }, $path
                  if $digest ne $path->relative( $self->path ) =~ s{/}{}gr;
            }
        },
        { recurse => 1 },
    );
}

1;
