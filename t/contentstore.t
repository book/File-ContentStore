use strict;
use warnings;
use Test::More;

use Path::Tiny ();
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

# check mode
is( $dir{src}->child('img-01.jpg')->stat->mode & 07777,
    0444, 'Files now read-only' );

# fsck
is_deeply( $store->fsck, {}, 'fsck' );

# fsck errors
unlink $dir{src}->child('IMG_0025.JPG');    # orphan file
$store->path->child( '01', '23' )->mkpath;
rename(                                     # corrupted + empty dir
    $store->path->child(
        'f7', '7a',
        '5294e550ee91c030e4d76da836961175f33f8382e0827919530f382665d4'
    ),
    $store->path->child(
        '01', '23',
        '456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    )
);

is_deeply(
    $store->fsck,
    {
        empty  => [ $store->path->child( 'f7', '7a' ) ],
        orphan => [
            $store->path->child(
                '10',
                '31',
                '525d736cbf09471f420b2ec762ac30ce50b78aa4dea3374596d2ad8906ee'
            )
        ],
        corrupted => [
            $store->path->child(
                '01',
                '23',
                '456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
            )
        ],
    },
    'fsck, 1 empty, 1 orphan, 1 corrupted'
);

# collision tests
%dir = build_work_tree( << 'TREE' );
md5-1
md5-2 subdir/md5-2
TREE

my $md5_store = File::ContentStore->new(
    path           => $dir{obj},
    digest         => 'MD5',
    make_read_only => '',
);

ok( !eval { $md5_store->link_dir($dir{src}); 1; }, 'link_dir failed' );
like(
    $@,
    qr{^Collision found for $dir{src}/subdir/md5-2 and ${\$md5_store->path}/00/8ee33a9d58b51cfeb425b0959121c9: content differs },
    '... on an MD5 collision'
);

isnt( $dir{src}->child('md5-1')->stat->mode & 07777,
    0444, 'Files not read-only' );

$md5_store = File::ContentStore->new(
    path                 => $dir{obj},
    digest               => 'MD5',
    check_for_collisions => '',
);
ok(
    eval { $md5_store->link_dir( $dir{src} ); 1; },
    'link_dir succeeded without collision check'
);
is(
    $dir{src}->child('md5-1')->stat->ino,
    $dir{src}->child('subdir/md5-2')->stat->ino,
    "different files linked togetther!"
);
is( $dir{src}->child('md5-1')->stat->mode & 07777,
    0444, 'Files now read-only' );


done_testing;
