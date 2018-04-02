use strict;
use warnings;
use Test::More;

use Path::Tiny;
use File::ContentStore;

sub build_work_tree {

    # where the data files live
    my $file = Path::Tiny->new( 't', 'files' );

    # setup our temporary directories
    my %dir = ( tmp => Path::Tiny->tempdir );
    ( $dir{$_} = $dir{tmp}->child($_) )->mkpath for qw( obj src );

    # process the mapping
    for ( split /\n/, shift ) {
        my ( $from, $to ) = map Path::Tiny->new($_), split / +/;
        $to ||= $from;
        $dir{src}->child( $to->parent )->mkpath;
        $file->child($from)->copy( $dir{src}->child($to) );
    }

    return %dir;
}

# copy some files to src
my %dir = build_work_tree( << 'TREE' );
img-01.jpg
img-01.jpg         img-02.jpg
IMG_0025.JPG
git-fusion.png
TREE

# create the ContentRepo
my $store = File::ContentStore->new(
    path   => $dir{obj},
    digest => 'SHA-256',
);
isa_ok( $store, 'File::ContentStore' );

# add all files in src
$store->link_dir( $dir{src} );

# check each file in src now has at least 2 links
$dir{src}->visit(
    sub { cmp_ok( $_->stat->nlink, '>=', 2, "$_ has at least 2 links" ) },
    { recurse => 1 },
);

# check duplicates
is(
    $dir{src}->child('img-01.jpg')->stat->ino,
    $dir{src}->child('img-02.jpg')->stat->ino,
    "img-01.jpg and img-02.jpg are linked"
);

done_testing;
