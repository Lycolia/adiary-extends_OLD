#-----------------------------------------------------------------------------
# AMPモジュール
#-----------------------------------------------------------------------------
sub {
	use strict;
#------------------------------------------------------------------------------
# ●コンストラクタ（無名クラスを生成する）
#------------------------------------------------------------------------------
my $mop;
my $name;
{
	my $aobj = shift;
	$name = shift;
	my $ROBJ = $aobj->{ROBJ};
	my $self = $ROBJ->loadpm('MOP', $aobj->{call_file});	# 無名クラス生成用obj
	$self->{aobj} = $aobj;
	$self->{this_tm} = $ROBJ->get_lastmodified($aobj->{call_file});

	$self->{trans_png} = $ROBJ->{Server_url} . $ROBJ->{Basepath} . $aobj->{pubdist_dir} . 'trans.png';
	$mop = $self;
}

#------------------------------------------------------------------------------
# ●ロゴ情報の取得
#------------------------------------------------------------------------------
$mop->{get_logo} = sub {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};
	my $blog = $aobj->{blog};

	my $file = $blog->{blog_image} || $aobj->{pubdist_dir} . 'default-logo.png';
	my $url  = $ROBJ->{Server_url} . $ROBJ->{Basepath} . $file;

	my $tm = $ROBJ->get_lastmodified( $file );
	if ($tm == $aobj->load_plgset('amp', 'logo_tm')) {
		return $url;
	}

	my $img = $aobj->load_image_magick();
	if (!$img) { return; }

	$img->Read( $ROBJ->get_filepath( $file ) );
	my ($x, $y) = $img->Get('width', 'height');

	$aobj->update_plgset('amp', 'logo_tm',    $tm);
	$aobj->update_plgset('amp', 'logo_width',  $x);
	$aobj->update_plgset('amp', 'logo_height', $y);
	return $url;
};

#------------------------------------------------------------------------------
# ●メイン画像の取得
#------------------------------------------------------------------------------
$mop->{get_main_image} = sub {
	my $self = shift;
	my $art  = shift;

	if ($art->{main_image}) { return ; }

	my $txt = $art->{amp_txt};
};

#------------------------------------------------------------------------------
# ●AMP用のCSSで不要なセレクタリスト
#------------------------------------------------------------------------------
	my @ignore_selector = qw(
.dropdown
button form input select option textarea #edit
.checkbox .button .colorbox .color-picker .colorpicker
#sidebar .hatena-module #com
article.setting	.help .highlight .search .ui-icon- .social-button
#album ul.dynatree #file #iframe #selected
.design .module-edit .ui-dialog .ui-progressbar .ui-tabs .jqueryui-tabs
.system table.calendar ul.hatena-section
#popup resize-parts #ui-icon-autoload
#dem-ddmenu
);

#------------------------------------------------------------------------------
# ●AMPの拡張SCRIPT
#------------------------------------------------------------------------------
	my %amp_scripts = (
'amp-ad'	=> '<script async custom-element="amp-ad" src="https://cdn.ampproject.org/v0/amp-ad-0.1.js"></script>',
'amp-audio'	=> '<script async custom-element="amp-audio" src="https://cdn.ampproject.org/v0/amp-audio-0.1.js"></script>',
'amp-video'	=> '<script async custom-element="amp-video" src="https://cdn.ampproject.org/v0/amp-video-0.1.js"></script>',
'amp-iframe'	=> '<script async custom-element="amp-iframe" src="https://cdn.ampproject.org/v0/amp-iframe-0.1.js"></script>',
'amp-youtube'	=> '<script async custom-element="amp-youtube" src="https://cdn.ampproject.org/v0/amp-youtube-0.1.js"></script>',
'amp-twitter'	=> '<script async custom-element="amp-twitter" src="https://cdn.ampproject.org/v0/amp-twitter-0.1.js"></script>'
);

#------------------------------------------------------------------------------
# ●AMP用のCSS生成
#------------------------------------------------------------------------------
$mop->{amp_css} = sub {
	my $self = shift;
	my $files= shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	my $amp_css_file = $aobj->{blogpub_dir} . 'amp.css';

	# ファイル更新チェック
	my $update;
	my $amp_css = $self->{this_tm} . "\n";
	foreach(@$files) {
		my $tm = $_ ? $ROBJ->get_lastmodified($_) : 0;
		$amp_css .= "$_?$tm\n";
	}
	chomp($amp_css);
	if ($aobj->load_plgset('amp', 'css_info') eq $amp_css) {
		return $ROBJ->fread_lines_cached($amp_css_file);
	}

	#------------------------------------------------------------
	# regenerate amp css
	#------------------------------------------------------------
	my $css;
	foreach(@$files) {
		if (!$_) { next; }
		local ($/) = "\0";
		my $lines = $ROBJ->fread_lines($_);
		my $dir = ($_ =~ m|^(.*/)[^/]+$|) ? $ROBJ->{Basepath} . $1 : '';
		foreach(@$lines) {
			# オプション内に画像ファイルを含む
			$_ =~ s!url\s*\(\s*(['"])([^'"]+)\1\s*\)!
				my $q = $1;
				my $file = $2;
				if ($file =~ m|^(?:\./)*[\w-]+(?:\.[\w-]+)*$|) {
					$file = $dir . $file;
				}
				"url($q$file$q)";
			!ieg;
			$css .= $_;
		}
	}
	my @str;
	$css =~ s!/\*.*?\*/|("[^"]*")!
		$1 && push(@str, $1) && "\x00$#str";
	!esg;
	$css =~ s|\@charset[^;]*;||ig;

	my @out;
	my $uiicon;
	$css =~ s!\s*(\@media[^\{]*{)?([^\{]*)(\{[^\}]*\})!
		my $media = $1;
		my $sels  = $2;
		my $attr  = $3;
		if ($media) {
			$media =~ s/\s+/ /g;
			$media =~ s/\s*([\{\};:,])\s*/$1/g;
			push(@out, $media);
		}
		if ($sels =~ /\}(.*)/s) {
			$out[$#out] .= '}';
			$sels = $1;
		}

		if ($sels =~ /#ui-icon-autoload/ && $attr =~ /background-color\s*:\s*#([0-9A-Fa-f]+);/) {
			$uiicon = $1;
		}

		my @ary;
		foreach my $sel (split(/,/,$sels)) {
			$sel =~ s/^\s*(.*?)\s*$/$1/;
			$sel =~ s/\s*>\s*/>/g;
			if ($sel =~ /^\.w\d+$/) { next; }	# .w20 .w400
			my $f;
			foreach(@ignore_selector) {
				if (index($sel, $_) < 0) { next; }
				$f=1;
				last;
			}
			if ($f) { next; }
			push(@ary, $sel);	# 残すセレクタ
		}
		$attr =~ s/\s+/ /g;
		$attr =~ s/\s*([\{\};:,])\s*/$1/g;
		$attr =~ s/\x00(\d+)/$str[$1]/g;	# 文字列復元
		@ary && push(@out, join(',',@ary) . $attr);
		'';
	!seg;
	if ($uiicon) {
		push(@out, $self->load_uiicon_css($uiicon));
	}
	$css = join("\n", @out);

	#------------------------------------------------------------
	# save amp css
	#------------------------------------------------------------
	$ROBJ->fwrite_lines($amp_css_file, $css);
	$aobj->update_plgset('amp', 'css_info', $amp_css);

	return $css;
};

#------------------------------------------------------------------------------
# ●ui-iconロード用cssの生成
#------------------------------------------------------------------------------
$mop->{load_uiicon_css} = sub {
	my $self = shift;
	my $col  = shift;

	$col =~ s/^([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])$/$1$1$2$2$3$3/;
	my @cols = (hex(substr($col,0,2)), hex(substr($col,2,2)), hex(substr($col,4,2)));
	my @vals = (0, 0x40, 0x80, 0xC0, 0xff);

	my $file='';
	foreach my $c (@cols) {
		my $diff=255;
		my $near;
		foreach(@vals) {
			my $d = $c - $_;
			$d = $d>0 ? $d : -$d;
			if ($d > $diff) { next; }
			$near = $_;
			$diff = $d;
		}
		$file .= unpack('H2', chr($near));
	}
	$file = $self->{ROBJ}->{Basepath} . $self->{aobj}->{pubdist_dir}
		. 'ui-icon/' . $file . '.png';
	return ".ui-icon,.art-nav a:before,.art-nav a:after{background-image:url(\"$file\")}";
};

#------------------------------------------------------------------------------
# ●AMP用のHTML生成
#------------------------------------------------------------------------------
$mop->{amp_txt} = sub {
	my $self = shift;
	my $art  = shift;
	my $aobj = $self->{aobj};
	my $ROBJ = $self->{ROBJ};
	my $DB   = $aobj->{DB};

	if ($art->{update_tm} < $art->{amp_tm}
	 && $self->{this_tm}  < $art->{amp_tm}) {
		return $art->{amp_txt};
	}

	# AMP用HTMLの生成
	my %head;
	$self->tag_wrapper_init();
	my $escaper = $aobj->_load_tag_escaper( $aobj->plugin_name_dir($name) . 'allow_tags.txt' );
	my $text = $escaper->escape( $art->{text}, {
		tag => sub {
			my $r = $self->tag_wrapper(@_);
			if ($r) { $head{$r}=1; }
		},
		close_tag => $self->{close_tag_wrapper}
	} );
	$ROBJ->trim( $text );

	# 記録
	my $blogid = $aobj->{blogid};
	$DB->update_match("${blogid}_art", {
		amp_txt  => $text,
		amp_head => join("\n", keys(%head)),
		amp_tm   => $ROBJ->{TM}
	}, 'pkey', $art->{pkey});
	
	$art->{amp_tm} = $ROBJ->{TM};
	return ($art->{amp_txt} = $text);
};

#------------------------------------------------------------------------------
# ●AMP用のHTML tag置換ルーチン
#------------------------------------------------------------------------------
# https://www.ampproject.org/docs/reference/components
#
my %replace;
$mop->{tag_wrapper_init} = sub {
	%replace = ();
};
$mop->{tag_wrapper} = sub {
	my $self = shift;
	my $ary  = shift;
	my $deny = shift;	# 不許可属性
	my $html = shift;	# このタグ以降のHTML
	my $ROBJ = $self->{ROBJ};

	my $head;
	my $tag  = $ary->[0];
	$tag =~ tr/A-Z/a-z/;

	my $h = $self->perse_attr($ary);

	#------------------------------------------------------------
	# img
	#------------------------------------------------------------
	if ($tag eq 'img') {
		if ($h->{width}  =~ /[^\d]/) { $h->{width} =0; }
		if ($h->{height} =~ /[^\d]/) { $h->{height}=0; }

		if (!$h->{width} || !$h->{height}) {
			$self->load_image_size($h);
		}
		$self->set_lastmodified($h);
		$tag = 'amp-img';
		$self->chain_attr($ary, $h);
		push(@$ary, '></amp-img');
	}
	#------------------------------------------------------------
	# Google AdSense
	#------------------------------------------------------------
	if ($tag eq 'ins' && $h->{class} eq 'adsbygoogle') {
		foreach(keys(%$h)) {
			if (substr($_,0,5) eq 'data-') { next; }
			delete $h->{$_};
		}
		$h->{type}   = "adsense";
		$h->{layout} = "responsive";
		$h->{width}  = 300;
		$h->{height} = 250;
		$self->chain_attr($ary, $h);

		$tag = $replace{$tag} = 'amp-ad';
	}
	#------------------------------------------------------------
	# audio
	#------------------------------------------------------------
	if ($tag eq 'audio') {
		$tag = $replace{$tag} = 'amp-audio';
	}
	#------------------------------------------------------------
	# video
	#------------------------------------------------------------
	if ($tag eq 'video') {
		$tag = $replace{$tag} = 'amp-video';

		$h->{poster} ||= $self->{trans_png};
		$self->layout($h, $deny, 180);

		$self->chain_attr($ary, $h);
	}
	#------------------------------------------------------------
	# iframe
	#------------------------------------------------------------
	if ($tag eq 'iframe') {
		my $url = $h->{src};
		#------------------------------------------------------------
		# YouTube
		#------------------------------------------------------------
		if ($url =~ m!^https?://(?:www\.youtube\.com|youtu\.be)/!) {
			$tag = $replace{$tag} = 'amp-youtube';

			delete $h->{src};
			$url =~ m/([\w]*)$/;
			$h->{"data-videoid"} = $1;

			$self->layout($h, $deny);
			$self->chain_attr($ary, $h);
		#------------------------------------------------------------
		# iframe
		#------------------------------------------------------------
		} else {
			$tag = $replace{$tag} = 'amp-iframe';

			$self->layout($h, $deny);
			$self->chain_attr($ary, $h);

			push(@$ary, "><amp-img layout=\"fill\" src=\"$self->{trans_png}\" placeholder></amp-img");
		}
	}
	#------------------------------------------------------------
	# source
	#------------------------------------------------------------
	if ($tag eq 'source') {
		my $url = $h->{src};
		if ($url !~ m|^//|i) {
			$url =~ s|^https?:||i;
			if (substr($url,0,2) ne '//') {
				$url = $ROBJ->{Server_url} . $url;
				$url =~ s|^https?:||i;
			}
			$h->{src} = $url;
			$self->chain_attr($ary, $h);
		}
	}
	#------------------------------------------------------------
	# Twitter
	#------------------------------------------------------------
	if ($tag eq 'blockquote' && $h->{class} eq 'twitter-tweet'
	 && $html =~ m|https://twitter\.com/[^/]*/status(?:es)?/(\d+)|) {
		$tag  = "amp-twitter layout=\"flex-item\" data-tweetid=\"$1\"><blockquote";

		$replace{blockquote} = 'blockquote></amp-twitter';
	}
	$ary->[0] = $tag;

	$tag =~ s/[^\w\-].*$//;
	return $amp_scripts{$tag};
};

#------------------------------------------------------------
# layoutの処理
#------------------------------------------------------------
$mop->{layout} = sub {
	my $self = shift;
	my $h    = shift;
	my $deny = shift;
	my $default = shift;

	my $h2 = $self->perse_attr($deny, 0);
	if ($h2->{style} =~  /(?:^|\s)width\s*:\s*(\d+)(?:px)?/i) { $h->{width} = $1; }
	if ($h2->{style} =~ /(?:^|\s)height\s*:\s*(\d+)(?:px)?/i) { $h->{height}= $1; }

	if ($h->{width} && $h->{height}) {
		$h->{layout} = 'responsive';
	} else {
		$h->{layout} = 'fixed-height';
		$h->{height} ||= $default || 240;
		delete $h->{width};
	}
};

#------------------------------------------------------------------------------
# ●閉じタグ
#------------------------------------------------------------------------------
$mop->{close_tag_wrapper} = sub {
	my $tag = shift;
	if ($replace{$tag}) {
		$tag = $replace{$tag};
		delete $replace{$tag};
		return $tag;
	}
	return $tag;
};

#------------------------------------------------------------------------------
# ●tagの属性解析
#------------------------------------------------------------------------------
$mop->{perse_attr} = sub {
	my $self = shift;
	my $ary  = shift;
	my $i    = $_[0] eq '' ? 1 : shift;
	my %h;
	foreach(; $i<=$#$ary; $i++) {
		if ($ary->[$i] =~ m/^([\w-]+)(?:="([^\"]*)")?$/) {
			my $k = $1;
			my $v = $2;
			$k =~ tr/A-Z/a-z/;
			$h{$k} = $v;
		} else {
			$h{error} = "tag format error!!!";
		}
	}
	return \%h;
};
#------------------------------------------------------------------------------
# ●tagの属性再結合
#------------------------------------------------------------------------------
$mop->{chain_attr} = sub {
	my $self = shift;
	my $ary  = shift;
	my $h    = shift;
	@$ary = ( $ary->[0] );	# $ary=[] is don't work!
	foreach(keys(%$h)) {
		my $v = $h->{$_};
		if ($v ne '') {
			push(@$ary, "$_=\"$v\"");
			next;
		}
		push(@$ary, $_);
	}
	return $ary;
};

#------------------------------------------------------------------------------
# ●更新日時の追加
#------------------------------------------------------------------------------
$mop->{set_lastmodified} = sub {
	my $self = shift;
	my $h    = shift;
	my $ROBJ = $self->{ROBJ};
	my $url  = $h->{src};

	if (index($url, '?') >= 0) { return; }

	my $basepath = $ROBJ->{Basepath};
	my $base_len = length($basepath);
	if (substr($url, 0, $base_len) eq $basepath) {
		my $file = substr($url, $base_len);
		$ROBJ->tag_unescape($file);
		$file =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;

		my $tm = $ROBJ->get_lastmodified($file);
		$url .= "?$tm";
		$h->{src} = $url;
	}
};

#------------------------------------------------------------------------------
# ●画像のサイズ取得
#------------------------------------------------------------------------------
$mop->{load_image_size} = sub {
	my $self = shift;
	my $h    = shift;	# tag attributes hash
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	# load image magick
	my $img = $aobj->load_image_magick();
	if (!$img) {
		$h->{error} = 'Image::Magick Load Error';
		return;
	}

	my ($x, $y) = $self->get_image_size($h->{src});
	if (!$h->{width})  { $h->{width} =$x; }
	if (!$h->{height}) { $h->{height}=$y; }
	return;
};

#------------------------------------------------------------------------------
# ●指定URLから画像サイズ取得
#------------------------------------------------------------------------------
$mop->{get_image_size} = sub {
	my $self = shift;
	my $url  = shift;
	my $ROBJ = $self->{ROBJ};
	my $aobj = $self->{aobj};

	my $img = $aobj->load_image_magick();
	if (!$img) {
		$ROBJ->error('Image::Magick Load Error');
		return;
	}

	my $basepath = $ROBJ->{Basepath};
	my $base_len = length($basepath);

	my $file = substr($url, $base_len);
	if (substr($url, 0, $base_len) ne $basepath) {
		if (substr($url,0,2) eq '//') { $url = 'http:' . $url; }
		if (substr($url,0,1) eq '/')  { $url = $ROBJ->{Server_url} . $url; }

		if ($url !~ m|^https?://|i) { return; }

		# 指定のURLから情報取得
		my $http = $ROBJ->loadpm('Base::HTTP');
		my ($status, $header, $data) = $http->get($url);
		if ($status != 200) { return; }

		$data = join('', @$data);
		my ($fh, $file) = $ROBJ->open_tmpfile();
		syswrite($fh, $data, length($data));
		seek($fh, 0, 0);
		$img->Read( file => $fh );
		close($fh);
		$ROBJ->file_delete($file);
	} else {
		$ROBJ->tag_unescape($file);
		$file =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/eg;
		$file =~ s|^/+||g;
		$file =~ s|\.+/||g;
		$img->Read( $ROBJ->get_filepath( $file ) );
	}

	my ($x, $y) = $img->Get('width', 'height');
	return ($x, $y);
};
###############################################################################
###############################################################################
	return $mop;
}

