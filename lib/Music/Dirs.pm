package Music::Dirs;

use myperl;

use base 'Exporter';
our @EXPORT =
(
	qw< $MUSICHOME $ALBUM_DIR $MISC_DIR $SINGLES_DIR $XMAS_DIR $TRACKLIST_DIR >,
	qw< is_album_dir is_tracklist single_dirs album_dirs track_dirs all_albums >
);


const our $MUSICHOME => dir($ENV{'MUSICHOME'});
const our $ALBUM_DIR => $MUSICHOME->subdir('Albums');
const our $MISC_DIR => $MUSICHOME->subdir('Misc');
const our $CHRISTY_DIR => $MUSICHOME->subdir('Christy');
const our $SINGLES_DIR => $MUSICHOME->subdir('Singles');
const our $XMAS_DIR => $MUSICHOME->subdir('xmas');
const our $TRACKLIST_DIR => $MUSICHOME->subdir('tracklists');


func album_dirs ()
{
	return ($ALBUM_DIR, $CHRISTY_DIR, $MISC_DIR);
}

func single_dirs ()
{
	return ($SINGLES_DIR, $XMAS_DIR);
}

func track_dirs ()
{
	return (album_dirs, single_dirs);
}

func all_albums ()
{
	return map { $_->children } album_dirs;
}


func is_album_dir ($dir)
{
	return -d $dir and grep { $_->resolve->contains($dir) } album_dirs;
}

func is_tracklist ($file)
{
	return -f $file and $file =~ /\.m3u$/ and $TRACKLIST_DIR->resolve->contains($file);
}


func find_track ($artist, $song)
{
	my @potentials;
	if ( $artist =~ s/\h+\[(.*?)\]// )
	{
		my $album = $1;
		push @potentials, glob("$_/*$album*/*$artist* - *$song*") foreach album_dirs;
	}
	else
	{
		push @potentials, glob("$_/*$artist*/*$artist* - *$song*") foreach album_dirs;
		push @potentials, glob("$_/*$artist* - *$song*")           foreach single_dirs;
	}
	# hopefully there's only one
	# but, if there's multiples, the caller will have to figure out what to do about it
	return @potentials;
}



1;
