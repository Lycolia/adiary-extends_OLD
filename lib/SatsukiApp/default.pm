use strict;
#------------------------------------------------------------------------------
# デフォルトmain
#							(C)2006-2017 nabe@abk
#------------------------------------------------------------------------------
package SatsukiApp::default;
#------------------------------------------------------------------------------
our $VERSION = '1.00';
###############################################################################
# ■基本処理
###############################################################################
#------------------------------------------------------------------------------
# ●【コンストラクタ】
#------------------------------------------------------------------------------
sub new {
	my ($class, $ROBJ, $self) = @_;
	if (ref($self) ne 'HASH') { $self={}; }
	bless($self, $class);	# $self をこのクラスと関連付ける
	$self->{ROBJ} = $ROBJ;
	return $self;
}
###############################################################################
# ■メイン処理
###############################################################################
sub main {
	my $self = shift;
	my $ROBJ  = $self->{ROBJ};

	#-------------------------------------------------------------
	# 初期処理
	#-------------------------------------------------------------
	# $ROBJ->make_csrf_check_key();
	# $ROBJ->read_form();

	#-------------------------------------------------------------
	# action処理
	#-------------------------------------------------------------
	my $action = $ROBJ->{Form}->{action};
	if ($ROBJ->{POST} && $action  ne '' && $action !~ /\W/) {
		$self->{action_data} = $ROBJ->call( 'action/' . $action );
	}

	#-------------------------------------------------------------
	# スケルトン選択
	#-------------------------------------------------------------
	my $skeleton = $self->{default_skeleton};
	if ($ENV{QUERY_STRING} =~ /^(\w+)/) {
		$skeleton = $1;
	}

	$self->output_html($skeleton);
	return 0;
}
#------------------------------------------------------------------------------
# ●HTMLの生成と出力
#------------------------------------------------------------------------------
sub output_html {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my ($skeleton) = @_;

	# スケルトンの確認
	if ($skeleton ne '') {
		my $file = $ROBJ->check_skeleton($skeleton);
		if (! defined $file) {
			$ROBJ->redirect( $ROBJ->{Myself} );
		}
	}

	# スケルトンの実効
	my $out;
	if ($self->{action_is_main}) {	# actionの中身で代用する
		$out = $self->{action_data};
	} else {
		$out = $ROBJ->call($skeleton);
	}

	# フレームあり？
	my $frame_name = $self->{frame_skeleton};
	if ($frame_name ne '') {
		$self->{inframe} = $out;
		$out = $ROBJ->call($frame_name);
	}
	$ROBJ->print_http_headers("text/html");
	$ROBJ->output_array($out);	# HTML出力
}

###############################################################################
# ■スケルトン用サブルーチン
###############################################################################

1;
