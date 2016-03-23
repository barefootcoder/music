package Music;

use myperl;

use Cwd;
use Carp;
use MP3::Tag;
use File::Spec;
use File::Find;
use File::HomeDir;
use File::Basename;
use Text::Capitalize;

use Music::Dirs;
use MusicCollection::Tag;

use base 'Exporter';
our @EXPORT = (@Music::Dirs::EXPORT,									# pass these along
qw<
	$ME set_album_dir usage_error fatal_error album_arg
	album title filename alpha_filename sort_tracklist generate_tracklist rename_album
	get_track_info
	get_tag foreach_album_tag compare_song_times denumerify format_sortkey
	attach_album_art extract_album_art
	rebuild_playlists find_tracklists_containing cover_file
>);


const our $ME => file($0)->basename;

# this can be changed to work with albums in places other than the default
# use one of these:
#		set_album_dir(to => $dir_containing_album_dirs);
#		set_album_dir(from => $dir_containing_one_album);
#		local $Music::AlbumDir = $dir_containing_album_dirs;
our $AlbumDir = $ALBUM_DIR;

func set_album_dir (:$from, :$to)
{
	if ($to)
	{
		$AlbumDir = dir($to);
	}
	elsif ($from)
	{
		$AlbumDir = dir($from)->parent;
	}
	else
	{
		my (undef, undef, undef, $me) = caller(0);
		die("$me: must supply `from' or `to' as args");
	}
}


func get_tag ($file_or_dir)
{
	return MusicCollection::Tag->new( -d $file_or_dir ? (dir => $file_or_dir) : (file => $file_or_dir) );
}

sub foreach_album_tag (&)
{
	my ($code) = shift;

	# this is sort of like a Schwartzian transform
	my %files;
	foreach my $album (grep { -d } all_albums)
	{
		my $tag = get_tag($album);
		warn("no tag for ", $album->basename) and next unless $tag;

		my $key = $tag->sortkey;
		if (exists $files{$key})					# two albums with the same sortkey!
		{											# just barf, after gathering enough info for an intelligent error
			my $orig = $files{$key}->dir->relative($MUSICHOME);
			my $new  = $album->relative($MUSICHOME);
			die("duplicate sortkey! [$key => $orig & $new]")
		}
		$files{$key} = $tag->file;
	}

	foreach (sort keys %files)
	{
		local $_ = get_tag($files{$_});
		$code->();
	}
}


func fatal_error (@msgs)
{
	say STDERR "$ME: $_" foreach @msgs;
	exit 1;
}

func usage_error ($msg)
{
	say STDERR "$ME: $msg (`$ME -h' for help, if you're lucky)";
	exit 2;
}


func album_arg ($arg)
{
	# normalize argument
	my $argtype;
	usage_error("must supply argument to operate on") unless $arg;
	debuggit(3 => "album_arg argument is", $arg);

	$arg =~ s{/$}{};			# trailing slash really borks ->basename
	$arg = file($arg);
	usage_error("can't read the file: $arg") unless -r $arg;

	if (is_tracklist($arg))
	{
		debuggit(4 => "album_arg argument is a tracklist");
		my $album = $arg->basename =~ s/\.m3u$//r;
		return wantarray ? ($album, 'tracklist') : $album;
	}
	elsif (is_album_dir($arg))
	{
		debuggit(4 => "album_arg argument is an album");
		my $album = $arg->basename;
		debuggit(3 => "album_arg album:", $album);
		return wantarray ? ($album, 'album') : $album;
	}
	elsif ($MUSICHOME->resolve->contains($arg))
	{
		debuggit(4 => "album_arg argument is underneath MUSICHOME");
		my $path = $arg->relative($MUSICHOME);
		return wantarray ? ($path, 'base') : $path;
	}

	fatal_error("I have no idea what '$1' is");
}


func _find_albumdir ($album)
{
	# look for existing dir first
	# $AlbumDir takes priority (even though it might be duplicated in album_dirs())
	my $dir = first { -d } map { $_->subdir($album) } ($AlbumDir, album_dirs());
	debuggit(3 => "_find_albumdir: existing", $album);
	# looks like this will be a new album dir to be created
	# always use $AlbumDir for that
	$dir //= $AlbumDir->subdir($album);
	return $dir;
}
func album ($type, $album)
{
	die("must have non-blank album name") unless $album;
	given ($type)
	{
		return _find_albumdir($album)								when 'dir';
		return $TRACKLIST_DIR->file('Albums', "$album.m3u")			when 'tracklist';
		when ('cover')
		{
			my $cover = capitalize($album);
			$cover = join('-', map { s/\W//g; $_ } split(' - ', $cover));
			return $MUSICHOME->file('covers', "$cover.jpg");
		}

		default { usage_error("illegal type $type to album()") }
	}
}


# given a title (album, artist, or song), consistencize it as regards
#	*	capitalization
#	*	whitespace
func _titlecase ($title)
{
	# a few extensions on the standard title_case
	my $title_split = qr{\s*/\s*};
	$title = join('', map { /$title_split/ ? $_ : title_case($_) } split(/($title_split)/, $title));
	$title =~ s/ & His / & his /;
	$title =~ s/ (Vs[.]?) /\L $1 /;
	return $title;
}
func title (@titles)
{
	return wantarray ? map { _titlecase($_) } @titles : _titlecase($titles[0]);
}


# turn a potential filename (or dirname) into a valid one by:
#	*	changing any /'s into |'s
#	*	remove any leading . (causes files to be "hidden" in Linux)
#	*	turning any international characters into their Latin equivalents
#	*	(and handling any cases where the above doesn't work that well)
func filename ($title)
{
	use Text::Unidecode;
	use charnames ':full';

	$title =~ s{/}{|}g;
	$title =~ s{^\.}{};
	$title =~ s{(\d+)\N{DEGREE SIGN}}{$1 Degrees}g;						# turn 4° into "4 Degrees" instead of "4deg"
	return unidecode($title);
}

# slight variation on filename(), generally used for albums:
#	*	all the same stuff as above, plus
#	*	remove any leading "The", so they'll sort correctly
#	*	invert artist name ("Joe Blow" into "Blow, Joe"), but *only* if requested
func alpha_filename ($album, :$invert = 0)
{
	$album = filename($album);
	$album =~ s/^the //i;
	$album =~ s/^(.+?) (\S+?) - /$2, $1 - / if $invert;
	return $album;
}


func sort_tracklist (@tracks)
{
	my $class = blessed $tracks[0] and $tracks[0]->isa('Path::Class::Entity');
	my %schwartzian;
	foreach (map { -d $_ ? dir($_)->children : file($_) } @tracks)
	{
		my $tag = get_tag($_);
		my $tracknum = $tag->tracknum || 0;
		my $discnum = $tag->discnum || 0;
		my $year = $tag->year || 0;
		my $sortkey = $tag->has_sortkey ? $tag->sortkey : sprintf("%04d%s", $year, $tag->album);
		$schwartzian{$_} = sprintf("%s%02d%02d", $sortkey, $discnum, $tracknum);
	}
	@tracks = sort { $schwartzian{$a} cmp $schwartzian{$b} } keys %schwartzian;
	return $class ? map { file($_) } @tracks : map { "$_" } @tracks;
}

func generate_tracklist ($album)
{
	$album = album_arg($album) if -d $album;							# JIC it's a directory
	my $albumdir = album(dir => $album);								# this will be the _proper_ directory
	debuggit(3 => "generate_tracklist:", $albumdir);

	my @tracks = sort_tracklist grep { /\.mp3$/ } $albumdir->children();
	debuggit(3 => "|-->", scalar @tracks, "tracks");

	my $tracklist_file = album(tracklist => $album);
	debuggit(3 => "|-->", $tracklist_file);
	open(OUT, ">$tracklist_file") or die("can't open tracklist file: $tracklist_file");
	say OUT $_ foreach @tracks;
	close(OUT);
}


func rename_album ($old, $new)
{
	my $old_dir = album(dir => $old);
	my $new_dir = album(dir => $new);
	die("can't find existing album $old") unless -d $old_dir;
	die("new name $new already exists") if -e $new_dir;

	debuggit(2 => "rename_album:", $old_dir, "[", $old, "]", "=>", $new_dir, "[", $new, "]");
	rename $old_dir, $new_dir;

	# fix tracklist
	my $old_tl = album(tracklist => $old);
	unlink $old_tl if -e $old_tl;
	generate_tracklist($new);

	# fix cover file (if it exists)
	my $old_cover = album(cover => $old);
	my $new_cover = album(cover => $new);
	debuggit(2 => "trying to rename", $old_cover, "to", $new_cover,
			"and old cover", -e $old_cover ? "does" : "does not", "exist");
	rename $old_cover, $new_cover if -e $old_cover;

	# fix any mentions in other tracklists
	foreach my $tl (find_tracklists_containing($old, qr{[^/]+}))
	{
		fix_tracklist($tl, $old, $new);
	}
}


func _generate_track_key ($new_track, $existing_tracks)
{
	my @clashes = grep { my $l = substr($_,0,1); $new_track =~ /^$l/i } keys %$existing_tracks;
	if (@clashes)
	{
		my $maxlen = 0;
		foreach my $clash (grep { my $l = substr($_,0,1); $new_track =~ /^$l/i } keys %$existing_tracks)
		{
			# so figure out how long a prefix we need not to clash any more
			my $len = 1;
			++$len while lc substr($new_track, 0, $len) eq lc substr($existing_tracks->{$clash}, 0, $len);
			# out with the old, in with the new
			# but only if the new length is _bigger_ than the old one
			if ($len > length($clash))
			{
				my $prefix = substr($existing_tracks->{$clash}, 0, $len);
				$existing_tracks->{$prefix} = delete $existing_tracks->{$clash};
			}

			# length of prefix for the new track is the longest length we find here
			$maxlen = max($maxlen, $len);
		}

		# now add the new track (shouldn't clash any more)
		my $prefix = substr($new_track, 0, $maxlen);
		die("something went very very wrong: $prefix => $existing_tracks->{$prefix}") if exists $existing_tracks->{$prefix};
		$existing_tracks->{$prefix} = $new_track;
	}
	else
	{
		# just jam it in there with one letter
		my $prefix = substr($new_track, 0, 1);
		$existing_tracks->{$prefix} = $new_track;
	}
	debuggit(4 => "after processing, struct is", DUMP => $existing_tracks);
}


func get_track_info ($url)
{
	use WWW::Mechanize;

	my $m = WWW::Mechanize->new;
	$m->get($url);
	my $doc = $m->content();
	($doc) = $doc =~ m{\bid\s*=\s*"?Track_listing\b(.*?)</(table|ol)>}s;
	$doc =~ s{<.*?>}{}sg;
	debuggit(4 => "doc is", $doc);

	my @tracks = $doc =~ m{"(.*?)"}g;
	debuggit(4 => "got tracks:", DUMP => \@tracks);

	# create hash of title => track
	# also, look for duplicate track names
	my $track_info = {};
	my %dups;
	foreach (keys @tracks)
	{
		my $track = $tracks[$_];
		if (exists $dups{$track})
		{
			if ($dups{$track} == 1)
			{
				my $first_num = delete $track_info->{$track};
				my $first_track = $track . " [1]";
				$track_info->{$first_track} = $first_num;
			}
			my $which = ++$dups{$track};
			$track .= " [$which]";
		}
		else
		{
			$dups{$track} = 1;
		}
		$track_info->{$track} = $_ + 1;				# convert from 0-based to 1-based
	}
	debuggit(6 => "track dups:", DUMP => \%dups);
	debuggit(3 => "track info:", DUMP => $track_info);

	return $track_info;
}


func seconds ($time)
{
	my ($min, $sec) = split(':', $time);
	return $min * 60 + $sec;
}

func compare_song_times ($lhs, $rhs)
{
	$lhs = seconds($lhs);
	$rhs = seconds($rhs);
	debuggit(3 => "comparing times:", $lhs, "to", $rhs);

	my $diff = $lhs - $rhs;
	return 0 if $diff >= -1 and $diff <= 1;								# only 1 second off counts as equal
	return $diff < 0 ? -1 : 1;											# else normalize to -1 or 1, like <=> or cmp
}


func denumerify ($text)
{
	use Lingua::EN::Numbers qw< num2en num2en_ordinal >;
	use Lingua::EN::Numbers::Years;
	use Time::ParseDate;

	$text =~ s/&/and/g;
	$text =~ s/([12]\d{3})/ year2en($1) /eg;
	$text =~ s/'(\d{2})/ year2en(time2str("%Y", parsedate("01-01-$1"))) /eg;
	$text =~ s/(\d+)(st|nd|rd|th)/ num2en_ordinal($1) /eg;
	$text =~ s/(\d+)/ num2en($1) /eg;
	return $text;
}

func format_sortkey ($text)
{
	# handle any annoying special cases
	return 'CHKCHKCHK' if $text eq '!!!';								# this is how they claim you should pronounce it

	# I don't think this order can be messed with much, if at all
	return uc denumerify(filename($text)) =~ s/, The$//r =~ s/^The //r =~ s/\W//gr;
}


func attach_album_art ($track, $image)
{
	my $tag = $track->isa('MusicCollection::Tag') ? $track : get_tag($track);
	die("no ID3v2 tag to attach album art to") unless $tag->has_v2;
	$tag->set_frame(APIC => chr(0), 'image/jpeg', chr(3), 'Cover Art', $image);
	$tag->save;
}

func extract_album_art ($track)
{
	my $tag = $track->isa('MusicCollection::Tag') ? $track : get_tag($track);
	debuggit(4 => "tag is", DUMP => $tag);

	return undef unless $tag->has_v2;
	my $frame = $tag->get_frame('APIC');
	return undef unless defined $frame;
	return ref $frame eq 'HASH' ? $frame->{'_Data'} : $frame;
}


func fix_tracklist ($filename, $old_album, $new_album)
{
	my @tracks =
		map { my $i = index($_, $old_album); substr($_, $i, length($old_album)) = $new_album unless $i == -1; $_ }
		slurp "$filename";
	open(OUT, ">$filename") and print OUT @tracks and close(OUT);
}


sub rebuild_playlists
{
	my $basedir = "$TRACKLIST_DIR";
	my $gqdir = (getpwnam($ENV{'USER'}))[7] . "/.gqmpeg/playlists";
	return unless -d $gqdir;

	# out with the old ...
	system("rm -rf $gqdir/*");

	# ... and in with the new
	my $sub = sub
	{
		my $newfile = $File::Find::name;
		$newfile =~ s@$basedir@$gqdir@;
		$newfile =~ s@\.m3u@.gqmpeg@;

		if (-d)
		{
			mkdir $newfile unless -d $newfile;
		}
		else
		{
			#print "ln -s '$File::Find::name' '$newfile'\n";
			system(qq{ln -s "$File::Find::name" "$newfile"});
		}
	};

	find($sub, $basedir);
}


sub find_tracklists_containing
{
	my ($album, $song) = @_;

	my @results;
	foreach my $tl (`find $TRACKLIST_DIR -type f -name "*.m3u"`)
	{
		chomp $tl;
		my $regex = qr{ $album/$song $ }x;
		debuggit(4 => "checking file", $tl, "for", $regex);

		push @results, $tl if grep { m{$album/$song$} } slurp $tl;
	}

	return @results;
}


sub cover_file
{
	my ($album_dir, $ext) = @_;

	my ($vol, $dirs) = File::Spec->splitpath($album_dir, 1);
	my @dirs = File::Spec->splitdir($dirs);

	my $file = pop @dirs;
	$file = join('', map { ucfirst } split(/ +/, $file));
	$file .= $ext;

	splice @dirs, -1, 1, 'covers';
	$dirs = File::Spec->catdir(@dirs);
	return File::Spec->catpath($vol, $dirs, $file);
}



#############################
## CLASSES
#############################


class MixTrack
{
	has artist			=>	( ro, isa => Str );
	has title			=>	( ro, isa => Str );
	#has list_status		=>	( ro, isa => enum([qw< added to_add to_find >]) );
	#has seq_status		=>	( ro, isa => enum([qw< leader solid iffy unknown wrong >]) );
	#has track_status	=>	( ro, isa => enum([qw< solid bridge title iffy >]) );
	# pseudo-attributes
	has filename	=>	( ro, lazy_build );

	# builders
	around BUILDARGS ($class: @_)
	{
		state $list_statuses =	{ ' ' => 'added', '>' => 'to_add', 'F' => 'to_find' };
		state $seq_statuses =	{ '*' => 'leader', '>' => 'solid', '~' => 'iffy', '?' => 'unknown', 'X' => 'wrong' };
		state $track_statuses =	{ ':' => 'solid', 'V' => 'bridge', '=' => 'title', '?' => 'iffy' };

		if (@_ == 1)
		{
			my ($list, $seq, $track) = qw< added unknown iffy >;		# default values for statuses
			if ( /^(.)(.)(.)\s\S/ )
			{
				$list = $list_statuses->{$1};
				$seq = $seq_statuses->{$2};
				$track = $track_statuses->{$3};
				$_ = substr($_, 4);
			}
			else
			{
				s/^\s+//;
			}
			/^(.*?) - (.*)$/;
			return $class->$orig(
					artist			=>	$2,
					title			=>	$1,
					list_status		=>	$list,
					seq_status		=>	$seq,
					track_status	=>	$track
			);
		}
		return $class->$orig(@_);
	}

	method _build_filename
	{
		use File::Glob 'bsd_glob';

		#my $basename = "$artist - $title.mp3";
		#my $filename = bsd_glob($AlbumDir->subdir($self->artist . " - *")->file($basename))
		#		|| bsd_glob($SINGLES_DIR->file($basename)) || die("can't locate track $basename");
		#return $filename;
	}
}

class Mixes
{
	use MooseX::Singleton;

	use Music::Dirs;

	has tracks	=>	( ro, isa => 'ArrayRef[MixTrack]', lazy_build );

	# builders
	method _build_tracks
	{
		my $prev;
		foreach ($MUSICHOME->file('mixes')->slurp(chomp => 1))
		{
			$prev = $_, next unless defined $_;

			if ( /^=+$/ )
			{
			}
		}
	}
}



1;
