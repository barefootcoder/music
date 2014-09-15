use myperl;


class MusicCollection::Tag
{
	use Carp;
	use MP3::Tag;

	use Music::Dirs;


	# ATTRIBUTES
	has file		=>	( ro, isa => 'Path::Class::File' );
	has _tag		=>	( rw, isa => 'MP3::Tag', lazy, builder => '_get_tag',
								handles =>	{
												tracknum => 'track1', discnum => 'disk1',
												map { $_ => $_ }
													qw< config artist title album year genre comment >,
													qw< artist_set title_set album_set year_set genre_set track_set >,
													qw< comment_set >,
											},
						);
	has status		=>	( rw, isa => Str, lazy, builder => '_guess_status', );


	# CTORS & BUILDERS

	around BUILDARGS ($class: %args)
	{
		if ( $args{'file'} and not $args{'file'}->isa('Path::Class::File') )
		{
			$args{'file'} = file($args{'file'});
		}

		$class->$orig(%args);
	}


	method _get_tag
	{
		my $file = $self->file;
		my $tag = MP3::Tag->new("$file");
		croak("couldn't get tag for $file [$!]") unless $tag;

		$tag->get_tags;
		return $tag;
	}


	method _guess_status
	{
		my $status;
		if (not $self->has_v2)
		{
			$status = 'untagged';
		}
		elsif ($self->get_frame('TXXX[MusicBrainz Artist Id]'))
		{
			$status = $self->get_frame('TMED') // $self->get_frame('TORY') // $self->get_frame('TXXX[SCRIPT]')
					? 'DIRTY'
					: 'clean';
		}
		else
		{
			$status = 'manual';
		}

		return $status;
	}


	# HELPER METHODS

	method _is_binary ($data)
	{
		return undef unless defined $data;
		# see http://www.justskins.com/forums/is-data-binary-or-47078.html
		local $_ = $data;
		length > 5 && (tr/ -~//c / length) >= .3;
	}

	method _dirs_are_equal ($dir1, $dir2)
	{
		return $dir1->absolute->resolve eq $dir2->absolute->resolve;
	}


	# PSEUDO-ACCESSORS

	method has_v1		{ exists $self->_tag->{ID3v1} }
	method has_v2		{ exists $self->_tag->{ID3v2} }

	method v1_data		{ $self->_tag->{ID3v1}->all }


	method album_path	{ $self->_dirs_are_equal( $self->file->dir, $SINGLES_DIR ) ? undef : $self->file->dir }
	method album_dir	{ $self->album_path ? $self->album_path->basename : undef }

	method filename
	{
		# have to qualify the method from Music so that it isn't confused with this one
		return Music::filename($self->_tag->interpolate('%a - %t%E'));
	}


	method sortkey		{ $self->get_frame('TSO2') // uc $self->album_dir }


	# ACTION METHODS

	method save
	{
		$self->config( write_v24 => 1 );
		delete $self->_tag->{'ImageExifTool'};		# cheap hack to avoid unsightly (and pointless) warning
		$self->_tag->update_tags;
	}


	method print_frames ($prefix = '')
	{
		foreach my $name ($self->frames)
		{
			my $value = $self->get_frame($name);
			if (ref $value eq 'HASH')
			{
				my $keys = join(',', sort keys %$value);
				if ($keys eq 'Text,_Data')
				{
					$name = "${name}[$value->{Text}]";
					$value = $value->{_Data};
				}
				elsif ($keys =~ /Description,.*_Data/)
				{
					$name = "${name} {$value->{Description}}+";
					$value = $value->{_Data};
				}
				else
				{
					$value = "{$keys}";
				}
			}
			printf "$prefix%-40s => %s\n", $name, !defined $value ? '<<NULL>>' :
					$self->_is_binary($value) ? '<<BINARY>>' : substr($value, 0, 70);
		}
	}


	method frames
	{
		return $self->_tag->id3v2_frame_descriptors;
	}


	method get_frame ($frame)
	{
		return $self->_tag->select_id3v2_frame_by_descr($frame);
	}


	method set_frame ($frame, $newval)
	{
		$self->_tag->select_id3v2_frame_by_descr($frame, $newval);
	}


	method rm_frame ($frame)
	{
		$self->set_frame($frame, undef);
	}

}


1;
