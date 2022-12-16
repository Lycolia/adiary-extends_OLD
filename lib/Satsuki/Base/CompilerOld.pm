use strict;
#-------------------------------------------------------------------------------
# skeleton parser / 構文解析コンパイラ
#						(C)2006-2022 nabe@abk
#-------------------------------------------------------------------------------
package Satsuki::Base::CompilerOld;
our $VERSION = '2.20';
#(簡易履歴)
# 2022/06 Ver2.20  <@h.01> のようなハッシュ参照を正しく処理
# 2022/02 Ver2.19  end 直後に elsif があるときのブロック切り出しバグ修正
# 2021/10 Ver2.18  複数種類の begin_array/hash 引数があるときのバグ修正
# 2021/09 Ver2.17  ハッシュデリファレンスを追加
# 2021/06 Ver2.16  copy() を clone() に変更
# 2021/04 Ver2.15  大文字のローカル変数を許可
# 2021/03 Ver2.14  foreach_hash(local(t,u), hash) 書式の追加
# 2020/12 Ver2.13  into_single_quot_string() の修正（0で始まる数字）。
# 2020/10 Ver2.12  '..'演算子削除。from_to() 追加。_ で始まるローカル変数許可
# 2020/09 Ver2.11  forexec_hash(), forexec_num() の削除
# 2020/09 Ver2.10  parse_block()追加。foreach_keys, foreach_values 追加
# 2020/09 Ver2.03  プラグマのバグ修正と動作変更。
# 2020/08 Ver2.02  delete_hash, ifdelete_hash 追加
# 2020/08 Ver2.01  ifexecブロック自動認識。'Is_function' to 'IsFunction'
# 2020/07 Ver2.00  elsif 追加, foreach_num(t, 10, 20)の書式追加。
# 2020/05 Ver1.93  weaken()追加
# 2020/05 Ver1.92  esc_csv()追加
# 2020/04 Ver1.91  const()処理修正
# 2020/04 Ver1.90  poland_to_eval() の大幅書き換え。
# 2020/03 Ver1.84  hash() array() {} [] 表記の入れ子を可能に。
# 2020/03 Ver1.83  push_hash(), unshift_hash()追加。
# 2020/02 Ver1.82  foreach追加。ifexec/forexecのbegin省略可。x++/--yの追加。
# 2019/06 Ver1.81  grep() を修正
# 2019/01 Ver1.80  出力先を配列からスカラに変更
# 2019/01 Ver1.76  match() の修正
# 2018/12 Ver1.75  hash(), {a=>b} の仕様変更（{}は元に戻す）
# 2018/10 Ver1.74  arrayq(), flagq(), hashq()のアップデート, ifset_header類追加
# 2016/01 Ver1.73  load_from_aryのバグ修正
# 2015/11 Ver1.72  関数展開時の出力書式を綺麗に（実行結果に変化なし）
# 2015/05 Ver1.71  <@ifcall(cond,f)>バグ修正。begin_array等で最後の空白行を除去。
# 2014/09 Ver1.70  begin_hash/array/string中にコマンドを書けるように。
# 2014/08 Ver1.63  begin_hashの順序保存を標準でoffに。
# 2013/08 Ver1.62  サブルーチン展開関連bugfix。<$break>の警告。pragma行処理bugfix
# 2013/08 Ver1.61  サブルーチンの展開位置を宣言場所に変更（クロージャ対応）
# 2013/07 Ver1.60  サブルーチンをメイン関数内記述に変更
# 2011/08 Ver1.51  breakチェックをブラックリスト式に
# 2010/xx Ver1.50  Ver2システム(adiary V3)準拠
################################################################################
# ■基本処理
################################################################################
#-------------------------------------------------------------------------------
# ●【コンストラクタ】
#-------------------------------------------------------------------------------
sub new {
	my $self = bless({}, shift);
	$self->{ROBJ} = shift;
	$self->{__CACHE_PM} = 1;

	return $self;
}

################################################################################
# ■メインルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●コンパイル処理
#-------------------------------------------------------------------------------
# compile( \@source_lines );
#
sub compile {
	my ($self, $lines, $src_file, $debugfile) = @_;
	# エラー保存領域初期化
	$self->{errors}   = 0;
	$self->{warnings} = 0;
	# エラー表示用
	$self->{src_file} = $src_file;
	# 組み込み関数使用状況の初期化
	$self->{use_builtin_ary}  = [];
	$self->{use_builtin_hash} = {};

	# 入力データチェック
	if (ref $lines ne 'ARRAY') {
		$self->error(undef, 'To complile array only');
		return (-1);	# 致命的エラー
	}

	# プリプロセッサ
	my ($buf, $lnum, $strbuf) = $self->preprocessor($lines);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_01.log", $buf, $lnum, $strbuf); }

	# 逆ポーランド記法に変換
	$self->convert_reversed_poland($buf, $lnum, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_02.log", $buf, $lnum, $strbuf); }

	# ブロックの対応チェック
	$self->parse_block($buf, $lnum, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_03.log", $buf, $lnum, $strbuf); }

	# eval 実行式に変換（from 逆ポーランド記法）, 文字列の評価
	$self->poland_to_eval($buf, $lnum, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_04.log", $buf, $lnum, $strbuf); }

	# 文字列を元に戻し、beginブロックを処理
	my $arybuf = $self->split_begin_block($buf, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_05.log", $buf, undef, $strbuf, $arybuf); }

	# 最適化処理
	$arybuf = $self->optimize($arybuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_06.log", undef, undef, $strbuf, $arybuf); }

	# ブロックをサブルーチンに変換
	$arybuf = $self->array2sub($arybuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_07.log", undef, undef, $strbuf, $arybuf); }

	# 最終処理（文字列を元に戻す）
	$arybuf = $self->recover_string($arybuf, $strbuf);
	if ($debugfile ne '') { $self->debug_save("${debugfile}_08.log", undef, undef, [], $arybuf); }

	if ($self->{ROBJ}->{CompilerTest}) {
		print join('', @$arybuf);
	}


	return ($self->{errors}, $self->{warnings}, $arybuf);
}
################################################################################
# ■演算子データ部
################################################################################
#-------------------------------------------------------------------------------
# ●変数定数
#-------------------------------------------------------------------------------
my $VAR_OUT  = '$$O';
my $VAR_LNUM = '$$L';
my $SUB_HEAD = <<'SUB_HEAD';
sub {
	my $R = shift;
	my $O = shift;
	my $L = shift;
	my $v = $R->{v};
	$_[0] = \$v;
SUB_HEAD

#-------------------------------------------------------------------------------
# ●プラグマ定数
#-------------------------------------------------------------------------------
my $P_del_begin_space = 0x0001;	# コマンド前の行頭がスペースのみの場合、それを除去する
my $P_del_lf_cmdline  = 0x0002;	# コマンドのみの行の行頭空白や文末改行を自動除去する
my $P_del_lf_aftercmd = 0x0004;	# コマンドのみの行に続く空行を除去する
my $P_del_blank       = 0x0008;	# 空行を除去
my $P_nocr            = 0x0010;	# 改行を除去する
my $P_cmd_only        = 0x0020;	# コマンド以外を無視
my $P_is_function     = 0x0040;	# 関数として処理

#-------------------------------------------------------------------------------
# ●演算子情報
#-------------------------------------------------------------------------------
my %OPR;		# 優先度配列
my %OPR_rename;	# 演算子正式名（存在するもののみ）
# bit 0 - 右から左
# bit 1 - 単項演算子
# bit 2 - 単項右結合（x++/x--用）
# bit 3 - 連結時にspaceが必要
# bit 4?12 - 演算子優先度（大きいほうが優先）
$OPR{'('}   =  0x00;
$OPR{')'}   =  0x00;
$OPR{'{'}   =  0x00;
$OPR{'}'}   =  0x00;
$OPR{'['}   =  0x00;
$OPR{']'}   =  0x00;
$OPR{';'}   =  0x00;
$OPR{','}   =  0x10;	# 例外処理
$OPR{'=>'}  =  0x10;
$OPR{'='}   =  0x21;
$OPR{'+='}  =  0x21;
$OPR{'-='}  =  0x21;
$OPR{'*='}  =  0x21;
$OPR{'/='}  =  0x21;
$OPR{'%='}  =  0x21;
$OPR{'&='}  =  0x21;
$OPR{'|='}  =  0x21;
$OPR{'%.='} =  0x21; $OPR_rename{'%.='} = '.=';
$OPR{'**='} =  0x21;
$OPR{'<<='} =  0x21;
$OPR{'>>='} =  0x21;
$OPR{'&&='} =  0x21;
$OPR{'||='} =  0x21;
$OPR{'||'}  =  0x38;
$OPR{'&&'}  =  0x48;
$OPR{'|'}   =  0x50;
$OPR{'^'}   =  0x60;
$OPR{'&'}   =  0x70;
$OPR{'=='}  =  0x80;
$OPR{'!='}  =  0x80;
$OPR{'<=>'} =  0x80;
$OPR{'%e'}  =  0x88; $OPR_rename{'%e'} = 'eq';
$OPR{'%n'}  =  0x88; $OPR_rename{'%n'} = 'ne';
$OPR{'<'}   =  0x90;
$OPR{'>'}   =  0x90;
$OPR{'<='}  =  0x90;
$OPR{'>='}  =  0x90;
$OPR{'%d'}  =  0xa2; $OPR_rename{'%d'} = 'defined';
$OPR{'>>'}  =  0xb0;
$OPR{'<<'}  =  0xb0;
$OPR{'+'}   =  0xc0;
$OPR{'-'}   =  0xc0;
$OPR{'%.'}  =  0xc8; $OPR_rename{'%.'} = '.';	# 数字定数との結合時に空白が必要
$OPR{'*'}   =  0xd0;
$OPR{'/'}   =  0xd0;
$OPR{'%'}   =  0xd0;
$OPR{'%x'}  =  0xd8; $OPR_rename{'%x'} = 'x';
$OPR{'++'}  =  0xe2;
$OPR{'--'}  =  0xe2;
$OPR{'++r'} =  0xe6; $OPR_rename{'++r'} = '++'; # x++
$OPR{'--r'} =  0xe6; $OPR_rename{'--r'} = '--'; # x++
$OPR{'!'}   =  0xf2;	# boolean not
$OPR{'~'}   =  0xf2;	# bit invert
$OPR{'**'}  = 0x100;
$OPR{'%r'}  = 0x200;	# 例外処理
$OPR{' '}   = 0x200;	# 例外処理
$OPR{'#'}   = 0x200;				# 配列参照（例外処理）
$OPR{'->'}  = 0x200;				# ハッシュ参照／変数（例外処理）
$OPR{'%h'}  = 0x200;				# ハッシュ参照／メソッドcall（例外処理）
$OPR{'%%'}  = 0x202; $OPR_rename{'%%'} = '%';	# ハッシュデリファレンス（例外処理）
$OPR{'@'}   = 0x202;				# 配列デリファレンス（例外処理）
$OPR{'##'}  = 0x202; 				# 配列の要素数-1（例外処理）
$OPR{'%m'}  = 0x202; $OPR_rename{'%m'} = '-';	# 負の数値

#-------------------------------------------------------------------------------
# ●呼び出しを許可する perl の core 関数
#-------------------------------------------------------------------------------
#		  0 : 許可（そのまま）
#	bit 0 =   1 : 戻り値が array
#	bit 1 =   2 : 第1引数が array
#	bit 2 =   4 : 第2引数が array
#	bit 3-7     : 第n引数が array
#	bit 8 = 256 : 第１引数が hash
#	bit 9 = 512 : 第２引数が hash
#	bit10 =1024 : 第３引数が hash
#	-1 : 関数ではなく裸制御文

my %CoreFuncs = (undef => 0, length => 0, sprintf => 0, join => 252, split => 1,
index => 0, rindex => 0, shift => 2, unshift => 2, pop => 2, push => 2,
int => 0, abs => 0, sin => 0, cos => 0, log => 0, exp => 0, sqrt => 0, rand => 0,
undef => 0, substr => 0, chop => 0, chomp => 0, chr => 0, ord => 0,
uc => 0, lc => 0, keys => 0x101, values => 0x101, ref => 0, delete => 0, splice => 3,
next=>-1, last=>-1, exists=>0, reverse => 15, return => 0, umask => 0, sleep => 0);

#-------------------------------------------------------------------------------
# ●breakフラグをチェックする関数
#-------------------------------------------------------------------------------
# 関数名の部分一致
my @BreakFuncs = (
'break',
'jump',
'continue',
'call',
'exit',
'exec');

#-------------------------------------------------------------------------------
# ●入れ子を許可しない関数 / begin省略を許可する関数
#-------------------------------------------------------------------------------
# <$x = ifexec(...)> 等を許可しない。
# <$ifexec(...)> のみ許可する。
#	1:	--
#	2:	begin補完
#
my %LastOpFuncs = (
	forexec		=>2,
	foreach		=>2,
	foreach_hash	=>2,
	foreach_keys	=>2,
	foreach_values	=>2,
	foreach_num	=>2,
	ifexec		=>2,
	elsif		=>1
);

#-------------------------------------------------------------------------------
# ●if複合関数
#-------------------------------------------------------------------------------
# ifjump や ifmessage を展開する
my %InlineIf = (if=>-1, ifdef=>-1,
	ifcontinue=>1,
	ifbreak=>1, ifbreak_clear=>1, ifsuperbreak=>1, ifsuperbreak_clear=>1,
	ifjump=>1, ifjump_clear=>1, ifsuperjump=>1, ifsuperjump_clear=>1,
	ifcall=>1, ifredirect=>1, ifform_error=>1, ifform_clear=>1,
	ifmessage=>2, ifnotice=>2,

	ifpush_hash=>1, ifunshift_hash=>1, ifdelete_hash=>1,

	ifset_cookie=>1, ifclear_cookie=>1,
	ifset_header=>1, ifset_lastmodified=>2,
	ifset_content_type=>2, ifset_status=>2,

	ifset=>-1, ifnext=>-1, iflast=>-1, 
	ifpush=>4, ifpop=>4, ifshift=>4, ifunshift=>4,
	ifreturn=>3, ifumask=>3, ifprint=>3);
#  1 : ifxxx(exp, a1, a2, ... ) → if(exp) { xxx(a1, a2, ...); }
#  2 : ifxxx(exp, A, B)         → if(exp) { xxx(A); } else { xxx(B); }
#  3 : 1の型で、expがperl命令かつ引数そのまま
#  4 : 1の型で、expがperl命令かつ、第一引数が配列
# -1 : 特殊処理（コード参照）

#-------------------------------------------------------------------------------
# ●行情報フラグ
#-------------------------------------------------------------------------------
my $L_replace        = 0x0001;	# 置換処理
my $L_line_number    = 0x0002;	# 行情報が必要
my $L_break_check    = 0x0004;	# breakチェックが必要
my $L_no_change      = 0x0008;	# 加工禁止フラグ
my $L_const          = 0x0020;	# 定数置換である
my $L_indent         = 0x0100;	# indent 情報用のゲタ
my $L_indent_bits    = 8;	# ↑が何ビットシフトか

#-------------------------------------------------------------------------------
# ●その他情報
#-------------------------------------------------------------------------------
# 単位情報
my %Unit2Num = (K => 1024, M => 1024*1024, G => 1024*1024*1024, T => 1024*1024*1024*1024,
		week => 3600*24*7, day => 3600*24, hour => 3600, min => 60, sec => 1);

# 定義済ローカル変数（内部使用） + 大文字1文字は予約済
my %SpecialVars = (v=>1, _=>1);

# 行番号の桁数
my $LineNumOpt  = 1; 	# 桁数をソース行数に最適化
my $LineNumLen  = 4;
my $LineNumZero = '0' x $LineNumLen;

################################################################################
# ■インライン関数
################################################################################
# #0?#9までの引数が取れる
# 複雑な処理の場合は組み込み関数にすること
# 展開時に外側に「( )」自動で付く。
my %InlineFuncs = (
'is_int'   => '#0 =~ /^-?\d+$/',
'is_array' => "ref(#0) eq 'ARRAY'",
'is_hash'  => "ref(#0) eq 'HASH'",
'from_to'  => "[(#0)..(#1)]"
);

################################################################################
# ■組み込み関数
################################################################################
# 追加関数としてコンパイル済スケルトンの後ろに関数を付加する。
# 呼び出し側では、その関数のリファレンスを呼び出す。
#
my %BuiltinFunc;
#---------------------------------------------------------------------
# ●ifexecの処理（通常はインライン展開される）
#---------------------------------------------------------------------
$BuiltinFunc{ifexec} = <<'FUNC';
sub {
	my $self = shift;
	my ($exp, $obj1, $obj2) = @_;
	if (defined $obj1 && $exp) { return $self->execute( $obj1 ); }
	if (defined $obj2)         { return $self->execute( $obj2 ); }
	return ;
}
FUNC
#---------------------------------------------------------------------
# ●文字列を各文字の文字コードに分解
#---------------------------------------------------------------------
$BuiltinFunc{string2ordary} = <<'FUNC';
sub {
	my $txt = shift;
	return [ map { ord($_) } split('', $txt) ];
}
FUNC
#---------------------------------------------------------------------
# ●文字列マッチ
#---------------------------------------------------------------------
$BuiltinFunc{match} = <<'FUNC';
sub {
	my ($data, $reg) = @_;
	if ($data =~ /$reg/) {
		return [$',$1,$2,$3,$4,$5,$6,$7,$8,$9];
	}
	return ;
}
FUNC
#---------------------------------------------------------------------
# ●文字列置換
#---------------------------------------------------------------------
$BuiltinFunc{replace} = <<'FUNC';
sub {
	my ($data, $x, $y) = @_;
	if (ref $data ne 'ARRAY') {
		$data =~ s/$x/$y/sg;
		return $data;
	}
	foreach(@$data) {
		$_ =~ s/$x/$y/sg;
	}
	return $data;
}
FUNC
$BuiltinFunc{replace_one} = <<'FUNC';
sub {
	my ($data, $x, $y) = @_;
	if (ref $data ne 'ARRAY') {
		$data =~ s/$x/$y/;
		return $data;
	}
	foreach(@$data) {
		$_ =~ s/$x/$y/;
	}
	return $data;
}
FUNC
#---------------------------------------------------------------------
# ●文字列検索
#---------------------------------------------------------------------
$BuiltinFunc{grep} = <<'FUNC';
sub {
	my $x = shift;
	my $ary = $_[0];
	if (ref($ary) ne 'ARRAY') {
		$ary = \@_;
	}
	return [ grep {/$x/} @$ary ];
}
FUNC
#---------------------------------------------------------------------
# ●ハッシュ関係
#---------------------------------------------------------------------
$BuiltinFunc{clone} = <<'FUNC';
sub {
	my %h = %{ $_[0] };
	return \%h;
}
FUNC

$BuiltinFunc{array2hash} = <<'FUNC';
sub {
	my $ary = shift;
	if (!$ary || !@$ary) { return {} };
	my %h = map {$_ => 1} @$ary;
	return \%h;
}
FUNC

$BuiltinFunc{arrayhash2hash} = <<'FUNC';
sub {
	my ($ary, $key) = @_;
	if (!$ary || !@$ary) { return {} };
	my %h = map {$_->{$key} => $_} @$ary;
	return \%h;
}
FUNC

#---------------------------------------------------------------------
# ●順序付 hash に値追加, 削除
#---------------------------------------------------------------------
$BuiltinFunc{push_hash} = <<'FUNC';
sub {
	my ($h, $key, $val) = @_;
	if (ref($h) ne 'HASH') { return; };
	if (!exists($h->{$key}) && $h->{_order}) {
		push(@{$h->{_order}}, $key);
	}
	$h->{$key} = $val;
	return $h;
}
FUNC

$BuiltinFunc{unshift_hash} = <<'FUNC';
sub {
	my ($h, $key, $val) = @_;
	if (ref($h) ne 'HASH') { return; };
	if (!exists($h->{$key}) && $h->{_order}) {
		unshift(@{$h->{_order}}, $key);
	}
	$h->{$key} = $val;
	return $h;
}
FUNC

$BuiltinFunc{delete_hash} = <<'FUNC';
sub {
	my ($h, $key) = @_;
	if (ref($h) ne 'HASH') { return; };
	if (exists($h->{$key}) && $h->{_order}) {
		$h->{_order} = [ grep { $_ ne $key } @{$h->{_order}} ];
	}
	delete $h->{$key};
	return $h;
}
FUNC

#---------------------------------------------------------------------
# ●ハッシュや配列をソートする
#---------------------------------------------------------------------
$BuiltinFunc{sort_num} = <<'FUNC';
sub {
	my ($ary,$key) = @_;
	if ($key eq '') { return [ sort {$a<=>$b} @$ary ]; }
	return [ sort {$a->{$key} <=> $b->{$key}} @$ary ];
}
FUNC

$BuiltinFunc{sort_str} = <<'FUNC';
sub {
	my ($ary,$key) = @_;
	if ($key eq '') { return [ sort {$a cmp $b} @$ary ]; }
	return [ sort {$a->{$key} cmp $b->{$key}} @$ary ];
}
FUNC

#---------------------------------------------------------------------
# ●print
#---------------------------------------------------------------------
# 特別な状況以外では使用しないこと
$BuiltinFunc{print} = <<'FUNC';
sub {
	print @_;
}
FUNC
#---------------------------------------------------------------------
# ●ファイル存在確認
#---------------------------------------------------------------------
$BuiltinFunc{'file_exists.arg'} = '$R,';
$BuiltinFunc{file_exists} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	if (-e $file) { return 1; }
	return 0;
}
FUNC

$BuiltinFunc{'file_readable.arg'} = '$R,';
$BuiltinFunc{file_readable} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	if (-r $file) { return 1; }
	return 0;
}
FUNC

$BuiltinFunc{'file_writable.arg'} = '$R,';
$BuiltinFunc{file_writable} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	if (-w $file) { return 1; }
	return 0;
}
FUNC

$BuiltinFunc{'file_size.arg'} = '$R,';
$BuiltinFunc{file_size} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	return -s $file;
}
FUNC

#---------------------------------------------------------------------
# ●更新日時を付加
#---------------------------------------------------------------------
$BuiltinFunc{'add_lastmodified.arg'} = '$R,';
$BuiltinFunc{add_lastmodified} = <<'FUNC';
sub {
	my ($self, $file) = @_;
	return $file . '?' . $self->get_lastmodified( $file );
}
FUNC

#---------------------------------------------------------------------
# ●CSVのための文字エスケープ
#---------------------------------------------------------------------
$BuiltinFunc{esc_csv} = <<'FUNC';
sub {
	my $val  = shift;
	if (substr($val,0,1) ne '"' && $val !~ /[\n,]/) { return $val; }
	$val =~ s/"/""/g;
	return '"' . $val . '"';
}
FUNC

#---------------------------------------------------------------------
# ●配列から指定した数をランダムにロードする
#---------------------------------------------------------------------
$BuiltinFunc{load_from_ary} = <<'FUNC';
sub {
	my ($ary,$num) = @_;
	my $max = @$ary;
	if ($max <= $num) { return $ary; }
	my @a = @$ary;
	for(my $i=0; $i<$max; $i++) {
		my $r = int(rand($max));
		my $x = $a[$i];
		$a[$i] = $a[$r];
		$a[$r] = $x;
	}
	return [ splice(@a, 0, $num) ];
}
FUNC

#---------------------------------------------------------------------
# ●弱い参照に設定
#---------------------------------------------------------------------
$BuiltinFunc{weaken} = <<'FUNC';
sub {
	foreach(@_) {
		Scalar::Util::weaken($_);
	}
}
FUNC

################################################################################
# ■コンパイラ本体
################################################################################
#///////////////////////////////////////////////////////////////////////////////
# ●[01] プリプロセッサ
#///////////////////////////////////////////////////////////////////////////////
# ・コマンドは１つだけで配列の１要素（１行）になるよう加工する（コマンド登場前後は、行分け）
# ・文字列を配列に格納し、記号コードに置き換える
# ・入力文字列から文字コード 00h-03h を除去する（内部的に使用するため）
sub preprocessor {
	my ($self, $lines) = @_;

	my @strbuf;
	my @buf;
	my @line_no = ( 0 );
	#-------------------------------------------------------------
	# ○プリプロセッサ
	#-------------------------------------------------------------
	my $pragma = 0;
	my $line = 0;
	my $prev_cmd_only = 0;
	my $sharp_comment = 0;
	my $chain_line_flag = 0;
	foreach(@$lines) {
		$line++;	# 行カウンタ
		my $l2 = $line;	# $l2 は行連結に利用
		if (ref $_) {
			$self->error($line, "Source line allowed scalar only (contain reference)" );
			my $ref = ref $_;
			push(@buf, "<!-- compiler : this line is reference '$ref' -->\n");
			push(@line_no, $line);	# 元の行を記憶
			next;
		}
		# 行頭 # によるコメント on / off
		if ($_ =~ /^<\@\#>/)   { $sharp_comment = 1; next; }	# on
		if ($_ =~ /^<\@\-\#>/) { $sharp_comment = 0; next; }	# off
		# 行頭 # を無視する
		if ($sharp_comment && $_ =~ /^\s*\#/) { next; }

		# 手前の行と連結
		my $x =  $_;
		if ($chain_line_flag) {
			$x =~ s/^\s*//;
			$chain_line_flag = 0;
		}
		# 行末 <@\> のとき行連結し、手前と改行後のスペースを除去する
		if ($x =~ /^(.*?)\s*<\@\\>\r?\n$/) {
			$x = $1;
			$chain_line_flag = 1;
		}

		# 手前の行がコマンドのみの行ならば、続く空行を除去
		if (($pragma & $P_del_lf_aftercmd) && $prev_cmd_only && $x =~ /^\s*\n$/) { next; }
		$prev_cmd_only = 0;

		# 空行を除去
		if (($pragma & $P_del_blank) && $x =~ /^\r?\n?$/) { next; }

		# $end で終わる行は行末改行除去
		$x =~ s/(<[\$\@]end(?:\.\w+)?>)\r?\n$/$1/;

		# プラグマの処理
		if ($x =~ /^<\@([+-])?(\d[0-9A-Fa-f]*)(?:\.\w+)?>/) {
			my $n = oct("0x$2");
			if    ($1 eq '+') { $pragma |=  $n; }
			elsif ($1 eq '-') { $pragma &= ~$n; }
			else              { $pragma  =  $n; }
			if ($pragma & $P_is_function) {		# 関数処理なら
				$pragma |= $P_cmd_only;		# コマンド以外を無視
			}
			# push(@buf, sprintf("pragma = %x", $pragma));
			# push(@line_no, $line);
			next;
		}
		# コマンドの解析処理
		if ($x =~ /^(.*?)<\@>/) {	# コメント処理
			$x=$1;
			if ($x =~ /^\s*$/) { next; }
		}
		if ($pragma & $P_nocr) { $x =~ s/\n//g;}
		$x =~ s/[\x00-\x04]//g;		# 文字 00h-04h を除去
		$x =~ s|</\$>|<\$\$>|g;		# </$> → <$$>

		# コマンド以外の文字列があるか、判別フラグ
		my $line_is_cmd_only = 1;
		# コマンドの認識
		my $commands = 0;
		while ($x =~ /^(.*?)<([\$\@\#])(.*)/s) {	# コマンド
			$commands++;
			my $t = $1;		# 手前
			my $z = '<' . $2;	# 先頭部 - 確定
			my $y = $3;		# コマンド？
			my $end_mark = '>';
			if ($commands==1) {	# 行の最初のコマンドのみ
				if (($pragma & $P_del_begin_space) && $t =~ /^\s+$/) { $t = ''; }
			}
			if ($t ne '') {		# コマンドより前部分
				if ($t !~ /^\s+$/) {
					$line_is_cmd_only = 0;
				}
				push(@buf, $t);
				push(@line_no, $line);	# 元の行を記憶
			}

			# <@@xxx> のとき行末改行を除去しない
			if ($2 eq '@' && ord($y) == 0x40) {
				$y = substr($y,1);
				$line_is_cmd_only = 0;
			}
			while ($y =~ /(.*?)([>\"\'])(.*)/s) {
				if ($2 eq '>') {
					$z .= $1 . '>';
					$x  = $3;	# 残り
					if (index($z,'{')<0 || substr($z, -2) ne '=>') {	# {hash => xxx} ではない 
						# 確定部分の ( ) の対応が合っていれば
						my $tmp=$z;
						while($tmp =~ /^(.*?)\([^\(]*?\)(.*)/) { $tmp="$1$2"; }
						if (index($tmp, '(') <0) { last; }
					}
					$y  = $x;	# 引き続き処理
					next;
				}
				if ($2 ne '"' && $2 ne "'") {
					$z .= $1 . $2;
					$y  = $3;	# 残り
					next;
				}
				$z .= $1;		# コマンドの手前を出力
				my $quot = $2;		# " or '
				my $str = $3;
				if ($quot eq "'" && $str !~ /^((?:\\.|[^\\'])*)\'(.*)/s 
				 || $quot eq '"' && $str !~ /^((?:\\.|[^\\"])*)\"(.*)/s) {
					$self->error($line, 'String error');
					$z = "<!-- compiler : string error -->\n";
					$x =''; last;
				}
				$str = $1;	# 文字列の中身
				$y   = $2;	# 残り

				if ($quot eq "'" && substr($z,-1) eq '#') {	# シングルクォート
					chop($z);
					$quot = '"';	# #'string' を評価文字列 "string" として扱う
				}
				if ($quot eq '"') {	# ダブルクォーテーションの場合
					$str =~ s/\\([\"\\\$\@])/"\\x" . unpack('H2', $1)/eg;	# \$ などのエスケープ文字
					$str =~ s/<@([\w\.]+?(\#\d+)?)>/\x01<$1>/g;		# 評価する文字列（変数）
					$str =~ s/"/\\"/g;					# " をエスケープ
					$str =~ s/([\$\@])/"\\x" . unpack('H2', $1)/eg;		# $ @ をエスケープ
					push(@strbuf, "\"$str\"");	# 文字列保存
					$z .= "\x01$#strbuf\x01";
				} else {		# シングルクォーテーションの場合
					push(@strbuf, "'$str'");	# 文字列保存
					$z .= "\x01$#strbuf\x01";
				}
			}
			if (substr($z,-1) ne '>' || substr($z,-2) eq '=>') {
				if ($y =~ /(.*)\\\r?\n?$/) {		# コマンド続き
					$x = $z . $1 . $lines->[$l2];	# 次行の連結
					$lines->[$l2++]='';
					next;
				}
				$self->error($line, 'Command not ended (must write in one line)');
				$z = "<!-- compiler : command not ended? -->\n";
				$x = '';
			}
			push(@buf, $z);			# コマンド部分
			push(@line_no, $line);		# 元の行を記憶
		}
		# コマンドしかない行ならば
		if (($pragma & $P_del_lf_cmdline) && $commands && $line_is_cmd_only) {
			# 行末改行を除去する
			if ($x =~ /^[\r\n]+$/) { $x=''; }
		}
		if ($x ne '') {
			if ($x !~ /^\s+$/) { $line_is_cmd_only=0; }
			push(@buf, $x);		# 残り
			push(@line_no, $line);	# 元の行を記憶
		}
		$prev_cmd_only = $line_is_cmd_only;
	}
	$self->{pragma} = $pragma;	# プラグマを保存

	if ($LineNumOpt) {
		$LineNumLen  = length("$line");
		$LineNumZero = '0' x $LineNumLen;
	}

	return (\@buf, \@line_no, \@strbuf);
}

#///////////////////////////////////////////////////////////////////////////////
# ●[02] 逆ポーランド記法に変換
#///////////////////////////////////////////////////////////////////////////////
sub convert_reversed_poland {
	my ($self, $buf, $lnum, $strbuf) = @_;

	my $line = 0;			# 行カウンタ
	my $comment_flag = 0;
	foreach (@$buf) {
		$line++;
		if ($_ eq '<$>')     { $_=''; $comment_flag=1; next; }	# コメントの開始
		if ($_ eq '<$$>')    { $_=''; $comment_flag=0; next; }	# コメントの終了
		if ($comment_flag) { $_=''; next; }
		#---------------------------------------------------------------
		# コメントアウトの場合、除去
		#---------------------------------------------------------------
		if ($_ =~ /^<\#(.*)>$/) {
			undef $_; next;
		}
		#---------------------------------------------------------------
		# コマンドでない場合はそのまま
		#---------------------------------------------------------------
		if ($_ !~ /^<([\$\@])(.*)>$/) {
			next;
		}
		#---------------------------------------------------------------
		# <@\n>, <@\r>, <@\ >, <@\t>, <@\v>, <@\f>, <@\e>処理
		#---------------------------------------------------------------
		if ($_ =~ /^<\@\\([nr tvfe])>$/) {
			my %h = ('n'=>"\n",'r'=>"\r",' '=>" ",'t'=>"\t",'v'=>"\v",'f'=>"\f",'e'=>"\e");
			$_ = $h{$1};
			next;
		}
		#---------------------------------------------------------------
		# コマンド行ならば
		#---------------------------------------------------------------
		my $cmd_flag = $1;	# @ or $
		my $cmd = $2;		# コマンド
		# 変換のための置換処理
		$cmd =~ s/([^\w\)])\.([^\w=])/$1%.$2/g;	# 文字連結
		$cmd =~ s/%([A-Za-z][\w\.])/%%$1/g;	# ハッシュデリファレンス
		$cmd =~ s/\.=/%.=/g;			# 代入＋文字連結
		$cmd =~ s/(\W)eq(\W)/$1%e$2/g;		# 文字比較
		$cmd =~ s/(\W)ne(\W)/$1%n$2/g;		# 文字比較
		$cmd =~ s/(\W)defined(\W)/$1%d$2/g;	# 定義済
		# $cmd =~ s/(\W)x(\W)/$1%x$2/g;		# 文字列 x n
		# $cmd =~ s/(\W)-[\d.]+(\W)/$1%m$2$3/g;	# 負の数値
		$cmd =~ s/\.\(/->(/g;			# x.() → x %h () =ハッシュ参照
		$cmd =~ s/\)\./)->/g;			# ().y → x %h () =ハッシュ参照
		$cmd =~ s!->([\w\.]+)!			# ■■注意■■ get_object() の仕様と合わせること！
			my $x=$1;
			$x =~ s/\.(\.*)/')->('$1/g;
			"->('$x')";
		!eg;

		# flagq(a,b-c,dd,ee) → flag('a','b-c','dd','ee')
		$cmd =~ s!(arrayq|hashq|flagq)\(\s*([^\(\)]*?)\s*\)!
			my $c = $1;
			my @a = $self->array2quote_string(split(/[, ]/,$2));
			foreach(@a) {
				push(@$strbuf, $_);
				$_ = "\x01$#$strbuf\x01";
			}
			my $x=@a ? ("'" . join("','",@a) . "'") : '';
			chop($c);
			"$c($x)";
		!eg;

		# 空白削除
		$cmd =~ s/\s*//g;

		$cmd =~ s/shift\(\)/shift(argv)/g;		# shift() → shift(argv)
		$cmd =~ s/\(\)/(__undef__)/g;			# () → (__undef__)
		$cmd =~ s/\[\]/[__undef__]/g;			# [] → (__undef__)
		$cmd =~ s/\{\}/{__undef__}/g;			# {} →  (__undef__)
		$cmd =~ s/->\('([\w\.]+)'\)\(/%h$1%r(/g;	# ('x').func() への対応

		# 構文解析
		# my $z = $cmd; $z =~ s/\e/|/g; print "\n*** $z\n";	# debug
		my @op  = ('(');	# 演算子スタック
		my @opl = ( 0 );	# スタックの演算子優先度 保存用
		my @poland;		# 逆ポーランド記法記録用
		my $x = $cmd . ')';
		my $right_arc = 0;
		while ($x =~ /(.*?)([=,\(\)\[\]\{\}\+\-<>\^\*\/&|%!;\#\@ ])(.*)/s) {
			if ($1 ne '') { push(@poland,  $1); }	# 　演算子の手前を出力
			my $op = $2;
			if ($op eq ' ') { $op='%r'; }
			if (length($3) >1 && exists $OPR{$op . substr($3, 0, 2)}) {	# 3文字の演算子？
				$op .= substr($3, 0, 2);
				$x   = substr($3, 2);	# 残り
			} elsif ($3 ne '' && exists $OPR{$op . substr($3, 0, 1)}) {	# 2文字の演算子？
				$op .= substr($3, 0, 1);
				$x   = substr($3, 1);	# 残り
			} else {
				$x = $3;		# 残り
			}
			if ($op eq '-'  && $1 eq '' && !$right_arc) { $op = '%m'; }	# 数値の負数表現判別
			if ($op eq '++' && $1 ne '') { $op='++r'; }	# "x++"を判定
			if ($op eq '--' && $1 ne '') { $op='--r'; }	# "x--"を判定

			# 演算子優先度を取り出す（bit 0 は右優先判別のときに使用）
			my $opl = $OPR{$op};
			#
			# $op  読み込んだ演算子
			# $opl 演算子優先度
			# $1   演算子の前
			#
			if ($op eq '(') {
				push(@op, '('); push(@opl, 0);
				if ($1 ne '') {			# xxx() ならば関数実行
					push(@op, '%r');
					push(@opl, 0);
				}
			} elsif ($op eq '[' || $op eq '{') {
				push(@op, $op); push(@opl, 0);
				if ($1 ne '') {	last; }		# xxx[] xxx{} はエラー強制終了
				push(@poland,  $op eq '[' ? 'array' : 'hashx');
				push(@op, '%r');
				push(@opl, 0);
			} else {
				my $z = $opl & 1;	# 右から優先の場合 $z = 1
				if ($opl[$#opl] & $opl & 2) {	# スタックトップと現演算子が同時に単項演算子
					# 優先度に関係なく演算子を取り出さない
				} else {
					while ($#opl>=0 && $opl[$#opl] >= $opl + $z) {
						my $op0   = pop(@op);
						my $level = pop(@opl);
						if ($op0 eq '(' && $op eq ')') { last; }
						if ($op0 eq '[' && $op eq ']') { last; }
						if ($op0 eq '{' && $op eq '}') { last; }

						# 現演算子より優先度の低い演算子を出力
						push(@poland, $op0);	# 逆ポーランド記法
					}
				}
				# 新しい演算子を積む
				if ($op eq ')' || $op eq ']' || $op eq '}') {
					$right_arc = 1;
				} else {
					$right_arc = 0;
					push(@op,  $op);
					push(@opl, $opl);
				}
			}
			## print "poland exp.   : ", join(' ', @poland), "\n";
			## print "op stack dump : ", join(' ', @op), "\n";
		}
		#
		# 変換完了
		#
		if ($x ne '' || $#op >= 0) {	# 残った文字列 or 演算子スタックを確認
			# print "!error \$x=$x op=$#op\n";
			$self->error($lnum->[$line], 'Illigal expression');
			$_ = "<!-- compiler : command error -->";		# エラー行を置換
			next;
		}
		push(@poland, $cmd_flag);	# コマンドフラグを最後に追加
		$_ = \@poland;			# 変換結果に置換
	}
	return ;
}

#///////////////////////////////////////////////////////////////////////////////
# ●[03] ブロックの解析
#///////////////////////////////////////////////////////////////////////////////
sub parse_block {
	my $self = shift;
	my ($buf, $lnum, $strbuf) = @_;
	my $pragma = $self->{pragma};

	my @begins;
	foreach my $p (0..$#$buf) {
		my $po = $buf->[$p];
		# 逆ポーランド式でなければそのまま
		if (ref($po) ne 'ARRAY' || !@$po) {
			next;
		}
		my $polen = $#$po;
		my $func  = $po->[0];

		#---------------------------------------------------------------
		# else/elsif/end の対応検証
		#---------------------------------------------------------------
		if ($func eq 'elsif' && $po->[$polen-1] eq '%r') {
			my $begin = @begins && $begins[$#begins];

			if (!$begin || $begin->{func} ne 'ifexec' && $begin->{func} ne 'ifexec') {
				$self->error($lnum->[$p], "Exists '%s' without 'ifexec/begin'", $func);
				$buf->[$p] = "<!-- compiler : Exists '$func' exists, but corresponding 'ifexec/begin' does not exist -->";
			} elsif ($begin->{else}) {
				$self->error($lnum->[$p], "Exists '%s' after 'else'", $func);
				$buf->[$p] = "<!-- compiler : Exists '%s' after 'else' -->";
			}
			next;
		}
		if ($polen == 1) {
			if ($func =~ /^else(|\.\w+)$/) {
				my $begin = pop(@begins) || {};
				my $label = $1;

				if ($label ne $begin->{label} || $begin->{func} ne 'ifexec' && $begin->{func} ne 'ifexec') {
					$self->error($lnum->[$p], "Exists '%s' without 'ifexec/begin'", $func);
					$buf->[$p] = "<!-- compiler : Exists '$func' exists, but corresponding 'ifexec/begin' does not exist -->";
					next;
				} elsif ($begin->{else}) {
					$self->error($lnum->[$p], "Exists '%s' duplicate in 'ifexec'", $func);
					$buf->[$p] = "<!-- compiler : Exists '%s' duplicate in 'ifexec' -->";
					next;
				}
				if ($begin->{sup_else}) {
					push(@begins, $begin);
					my $ifp  = $begin->{p};
					my $ifpo = $buf->[$ifp];
					my $flag = pop(@$ifpo);
					my $z    = pop(@$ifpo);
					my $y    = pop(@$ifpo);
					push(@$ifpo, ',', "begin$label" , $y, $z, $flag);
					$po->[0] .= $label;
				}
				if (@begins) { $begins[$#begins]->{else} = 1; }
				next;

			}
			if ($func =~ /^end(_\w+)?(\.\w+)?$/) {
				my $begin = pop(@begins);
				my $type  = $1;
				my $label = $2;

				if (!$begin || $type && $type ne $begin->{type} || $begin->{label} ne $label) {
					$self->error($lnum->[$p], "Exists '%s' without 'begin'", $func);
					$buf->[$p] = "<!-- compiler : Exists '$func' exists, but corresponding 'begin' does not exist -->";
					next;
				}

				# ブロック解析のために <$end> を書き換える。
				if (!$type) {
					$po->[0] = 'end' . $begin->{type} . $label;
				}
				next;
			}
		}

		#---------------------------------------------------------------
		# begin補完
		#---------------------------------------------------------------
		my $sup_else;
		if ($LastOpFuncs{$func}==2 && 2<$polen) {
			my $flag = pop(@$po);
			my $z    = pop(@$po);
			my $y    = pop(@$po);
			if ($z eq '%r' && ($y ne ',' || $po->[$#$po] !~ /^begin/)) {
				push(@$po, $y, 'begin');
				$y=',';
				if ($func eq 'ifexec') { $sup_else=1; }	# else補完
			}
			push(@$po, $y, $z, $flag);
		}

		#---------------------------------------------------------------
		# begin抽出
		#---------------------------------------------------------------
		for(my $i=$polen; 0<=$i; $i--) {
			if ($po->[$i] !~ /^begin(_\w+)?(\.\w+)?$/) { next; }
			push(@begins, {
				func	=> $func,
				type	=> $1,
				label	=> $2,
				sup_else=> $sup_else,
				p	=> $p,
				i	=> $i
			});
		}
	}
}

#///////////////////////////////////////////////////////////////////////////////
# ●[04] 逆ポーランド記法を eval 形式に変換
#///////////////////////////////////////////////////////////////////////////////
sub poland_to_eval {
	my ($self, $buf, $lnum, $strbuf) = @_;
	my $pragma = $self->{pragma};

	my %constant;			# 定数バッファ
	my @lv_stack = ( {} );		# ローカル変数のバックアップ
	my $line = 0;			# 配列カウンタ
	foreach(@$buf) {
		$line++;
		if (ref $_ ne 'ARRAY' || !@$_) {	# 逆ポーランド式でなければそのまま
			next;
		}
		# 元ソース中の行番号の生成
		my $line_num = substr($LineNumZero.$lnum->[$line], -$LineNumLen);
		my $cmd_flag = pop(@$_);

		# 処理準備
		my @types = map { $self->get_element_type(\%constant, \@lv_stack, $strbuf, $_) } @$_;

		# elsifのスタック処理
		if ($_->[0] eq 'elsif' && $_->[$#$_] eq '%r') {
			pop(@lv_stack);
			push(@lv_stack, @lv_stack ? $lv_stack[$#lv_stack] :{});
		}

		# ローカル変数設定
		my $local_vars = $lv_stack[$#lv_stack] || {};

		## print "\npoland expression : ", join(' ', @$_),    "\n";
		## print   "data types        : ", join(' ', @types), "\n";
		if (grep {$_ eq "error"} @types) {
			my $error = 'Illigal expression';
			$self->error(int($line_num), $error);
			$_ = "<!-- compiler : $error -->";	# エラー行を置換
			next;
		}

		# 単一置換式 <@t.var> 等
		if ($#$_ == 0 && $types[0] eq 'obj') {
			my $var_name = pop(@$_);
			# 【警告】breakを変数として参照してる
			if ($var_name eq 'break') {
				$self->warning($line_num, '"break" variable referenced. Do you mean "break()" function?');
			}
			# xxx.yyy のときの xxx を判別
			if ($var_name =~ /^(\w+)/ && $local_vars->{$1}) {
				$_ = "\x03" . $var_name;
			} else {
				$_ = "\x02" . $var_name;
			}
			if ($cmd_flag eq "\$") { undef $_; }
			next;
		}

		# poland式
		$_ = $self->p2e_one_line($cmd_flag, $line_num, $_, \@types, \%constant, $local_vars, $strbuf);
	}
	return;
}

#-------------------------------------------------------------------------------
# ○eval変換（1行処理）
#-------------------------------------------------------------------------------
sub p2e_one_line {
	my $self = shift;

	my ($cmd_flag, $line_num, $poland, $types, $constant, $local_vars, $strbuf) = @_;

	my $stack = [];
	my $stype = [];
	my $st = {
		l_info		=> 0,
		cmd_flag	=> $cmd_flag,
		line_num	=> $line_num,
	};

	# 単一定数置換 <@111>, <@"x">
	if ($#$poland == 0 && $types->[0] eq 'const') {
		$st->{l_info} |= $L_const;
	}

	my $prev_op;
	foreach(0..$#$poland) {
		## print "  dump stack : ", join(' ', @$stack), "\n";
		## print "  type stack : ", join(' ', @$stype), "\n";

		my $p    = $poland->[$_];
		my $type = $types ->[$_];
		$st->{last_op} = ($_ == $#$poland);

		if ($type eq 'op') {		# 演算子
			my $orig_op = $p;
			my $op  = $p;
			my $opl = $OPR{$p};
			## printf("\top     = $op [%x]\n", $opl);

			# 正式な perl演算子名に変換
			if (exists $OPR_rename{$op}) { $op = $OPR_rename{$p}; }

			my $x  = pop(@$stack);
			my $xt = pop(@$stype);
			my $x_orig = $x;
			if (!defined $x) { last; }	# エラー
			if (ref $x eq 'ARRAY') {
				$x = join(',', $self->get_objects_array($x, $xt, $local_vars));
			}
			my ($y, $yt);
			if ((~$opl) & 2) {	# ２項演算子
				$y  = pop(@$stack);
				$yt = pop(@$stype);
				if (!defined $y) { last; }	# エラー
			}

			#-------------------------------------------------------
			# constant処理
			#-------------------------------------------------------
			if ($op eq '%r' && ($y eq 'constant' || $y eq 'const')) {
				if ($xt ne 'obj') {
					$st->{error_msg} = "$x is not object";
					last;
				}
				push(@$stack, $x);
				push(@$stype, 'const_var');
				next;
			}
			if ($yt eq 'const_var') {
				if (!$st->{last_op} || $op ne '=' || $xt ne 'const') {
					$st->{error_msg} = "illegal const()";
					last;
				}
				@$stack = ($x);
				@$stype = ('const');
				$constant->{$y} = $x;
				last;
			}

			#-------------------------------------------------------
			# 一般処理
			#-------------------------------------------------------
			if ($xt eq 'obj') { $x = $self->get_object($x,$local_vars); }	# オブジェクト評価

			#-------------------------------------------------------
			# 関数call
			#-------------------------------------------------------
			if ($op eq '%r') {
				$self->p2e_function($st, $local_vars, $stack, $stype, $x_orig, $x, $xt, $y, $yt);
				if ($st->{last} || $st->{error} || $st->{error_msg}) { last; }
				next;
			}

			if ($op eq ',' || $op eq '=>')  {
				if (ref($yt) eq 'ARRAY') {
					push(@$y,  $x_orig);
					push(@$yt, $xt);
				} else {
					$y  = [$y,  $x_orig];
					$yt = [$yt, $xt];
				}
				push(@$stack, $y);
				push(@$stype, $yt);
				next;
			}

			if ($yt eq 'obj') { $y = $self->get_object($y,$local_vars); }	# オブジェクト評価
			if ($op eq '#')  {	# 配列参照
				$x =~ s/^\((.*)\)$/$1/;	# 一番外の (  ) を外す
				if ($x eq '-1') {
					push(@$stack, "$y\-\>[\$#$y]");
				} else {
					push(@$stack, "$y\-\>[$x]");
				}
				push(@$stype, $orig_op);
				next;
			}
			if ($op eq '->')  {	# ハッシュ参照（変数）
				if ($yt eq 'string') {
					push(@$stack, "\$R->{$y}\-\>{$x}");
					push(@$stype, $orig_op);
				} else {
					push(@$stack, "$y\-\>{$x}");
					push(@$stype, $orig_op);
				}
				next;
			}
			if ($op eq '%h')  {	# ハッシュ参照（メソッドcall）
				push(@$stack, "$y\-\>$x_orig");
				push(@$stype, 'function-name');
				next;
			}
			if ($op eq '@')  {
				push(@$stack, "\@\{$x\}");
				push(@$stype, $orig_op);
				next;
			}
			if ($op eq '##')  {
				push(@$stack, "\$\#\{$x\}");
				push(@$stype, $orig_op);
				next;
			}

			#-------------------------------------------------------
			# 配列代入 (x,y,z) = func() 等
			#-------------------------------------------------------
			if ($op eq '=' && ref($y) eq 'ARRAY')  {
				if (grep { $_ != 'obj'} @$yt) {
					# エラー
					push(@$stack, $y);
					push(@$stype, $yt);
					last;
				}
				my @ary = $self->get_objects_array($y, $yt, $local_vars);
				$y = "(". join(',', @ary) . ")";

				# (x,y,z) = (1,2,3) : arrar to array
				if (ref($x_orig) eq 'ARRAY') {
					$x = "(". join(',', @$x_orig) . ")";
				}
			}

			#-------------------------------------------------------
			# ローカル変数への代入
			#-------------------------------------------------------
			if ($st->{last_op} && $op eq '=' && $y =~ /^\$[a-z][a-z0-9]*$/ && $y ne '$v') {
				push(@$stack, "$y=$x");
				push(@$stype, $orig_op);
				next;
			}
			#-------------------------------------------------------
			# 通常の２項演算子
			#-------------------------------------------------------
			if ((~$opl) & 2) {
				if ($opl & 1 && $op =~ /=$/ && $yt eq 'const') {	# 代入演算子
					$st->{error_msg} = "Can't modify constant";
					last;
				}
				if ($opl & 1) {			# 右結合
					my $xopl = $OPR{$xt};
					if ($xopl && $opl<$xopl) {
						$x =~ s/^\((.+)\)$/$1/;
					}
				} else {			# 左結合
					my $yopl = $OPR{$yt};
					if ( $opl == $yopl		# a + b + c や a . b . c のように同じ優先度の演算子が並んでいる
					  || $yopl && $opl<$yopl) {	# 直前の演算子のほうが優先度が高い
						$y =~ s/^\((.+)\)$/$1/;
					}
				}

				my $a  = ($opl & 8) ? "($y $op $x)" : "($y$op$x)";
				my $at = $orig_op;			# $op の記述名
				if ($xt eq 'const' && $yt eq 'const') {
					$a  = eval($a);
					if ($a eq '') { if ($a) { $a=1; } else { $a=0; } }	# true/false
					$at = 'const';
				}
				push(@$stack, $a);
				push(@$stype, $at);
				next;
			}
			#-------------------------------------------------------
			# 単項演算子
			#-------------------------------------------------------
			my $sp = ($opl & 8) ? ' ' : '';
			my $a  = ($opl & 4) ? "($x$sp$op)" : "($op$sp$x)";	# 左結合か右結合か
			my $at = $orig_op;
			if ($xt eq 'const') {
				$a  = eval($a);
				if ($a eq '') { if ($a) { $a=1; } else { $a=0; } }	# true/false
				$at = 'const';
			}
			push(@$stack, $a);
			push(@$stype, $at);
			next;

		} elsif ($type eq 'error') {	# エラー
			push(@$stack, $p);
			push(@$stype, $type);
			last;

		} else {	# オブジェクト指定
			push(@$stack, $p);
			push(@$stype, $type);
		}
	}

	#-----------------------------------------------------------------------
	# スタックに 2つ以上 残っている = エラー
	#-----------------------------------------------------------------------
	if ($#$stack != 0) {
		my $error = $st->{error_msg} || 'Illigal expression (%d)';
		$self->error(int($line_num), $error, $#$stack );
		$self->tag_escape(@$stack);
		return "<!-- compiler : command error($#$stack) " . join(' ', @$stack) . "-->";		# エラー行を置換
	}

	#-----------------------------------------------------------------------
	# 正常置換
	#-----------------------------------------------------------------------
	my $exp  = pop(@$stack);
	my $type = pop(@$stype);
	if (ref $exp eq 'ARRAY') {
		$exp = join(',', $self->get_objects_array($exp, $type, $local_vars));
		$type = "*";
	}
	if ($exp =~ /^\((.*)\)(;?)$/) { $exp = "$1$2"; }		# 一番外の (  ) を外す
	if ($type eq 'obj') { $exp = $self->get_object($exp,$local_vars); }	# オブジェクの場合、参照形式へ
	if ($type eq 'const') {		# 定数
		if ($cmd_flag eq "\$") { undef $_; next; }	# 無視
		# 2/8/16進数なら数値化
		if ($exp =~ /^0[xb]?\d+$/) {
			$exp = oct($exp);
		}
		# 文字列でなければ置き換え
		if ($exp !~ /^\x01(\d+)\x01$/) {		# 文字列
			return $exp;
		}
	}
	if ($type eq 'local') {		# <@local(x,y)>
		$cmd_flag='$';
	}
	my $cmd = "\x01$line_num" . $exp;

	# 行情報を保存
	if ($cmd_flag eq '@')  { $st->{l_info} |= $L_replace; }	# 結果を置換する
	if ($st->{l_info}) {
		$cmd .= "#$st->{l_info}";		# 行情報付加
	}
	return $cmd;
}

#-------------------------------------------------------------------------------
# ○eval変換（関数処理）
#-------------------------------------------------------------------------------
sub p2e_function {
	my $self = shift;
	my $st   = shift;
	my ($local_vars, $stack, $stype, $x_orig, $x, $xt, $y, $yt) = @_;

	#-----------------------------------------------------------------------
	# 入れ子を許可しない関数
	#-----------------------------------------------------------------------
	if (!$st->{last_op} && $LastOpFuncs{$y}) {
		$st->{error_msg}="Not allow nest $y() function";
		return;
	}

	#-----------------------------------------------------------------------
	# local変数処理
	#-----------------------------------------------------------------------
	if ($y eq 'local') {
		$x  = ref($x_orig) ? $x_orig : [$x_orig];
		$xt = ref($xt)     ? $xt     : [$xt];
		my %h;
		foreach(@$x) {
			if (shift(@$xt) ne 'obj') {
				$st->{error_msg}="Illegal local() format";
				return;
			}
			if ($_ !~ /^[A-Za-z_]\w*$/) {
				$st->{error_msg}="Illegal local var: $_";
				return;
			}
			if ($SpecialVars{$_} || $_ =~ /^[A-Z_]$/) {
				$st->{error_msg}="Reserved local var name: $_";
				return;
			}
			if ($h{$_}) {
				$st->{error_msg}="Duplicate local var: $_";
				return;
			}
			$h{$_} = 1;
		}
		if ($#$x == 0) {
			push(@$stack, "my \$$x_orig");
			$local_vars->{$x_orig}=1;
		} else {
			my $vars='';
			foreach(@$x) {
				$local_vars->{$_}=1;
				$vars .= "\$$_,";
			}
			chop($vars);
			push(@$stack, "my($vars)");
		}
		push(@$stype, 'local');
		return;
	}

	#-----------------------------------------------------------------------
	# ifexec
	#-----------------------------------------------------------------------
	if ($y eq 'ifexec') {
		my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		if ($#ary == 2 && $ary[2] =~ /^\x01\[(begin.*)\]$/) { $ary[2] = "\x02[$1]"; }
		if ($#ary <= 2 && $ary[1] =~ /^\x01\[(begin.*)\]$/) { $ary[1] = "\x02[$1]"; }
		$ary[0] =~ s/^\((.*)\)$/$1/;	# 一番外の (  ) を外す
		$x = join(",", @ary);
		@$stack = ("$y($x)");
		@$stype = ('!*');
		$st->{last}=1;
		return;
	}
	if ($y eq 'elsif') {
		my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		if ($#ary != 0) {
			push(@$stack, $x,  $y);
			push(@$stype, $xt, $yt);
			$st->{error_msg} = "'elsif' allow one argument only";
			return;
		}
		$x = join(",", @ary);
		@$stack = ("elsif($x)");
		@$stype = ('!*');
		$st->{last}=1;
		return;
	}

	#-----------------------------------------------------------------------
	# foreachの展開
	#-----------------------------------------------------------------------
	if ($y =~ /^foreach/ || $y eq 'forexec') {
		my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		my $line_num_int = int($st->{line_num});

		# ループ変数がローカル変数か判定
		my $localvar = ($ary[0] =~ /^(?:my +)?\$[a-z][a-z0-9]*$/);

		if ($#ary == 2 && $ary[2] =~ /^\x01\[(begin.*)\]$/) {
			my $begin = $1;

			if ($y eq 'foreach' || $y eq 'forexec') {
				my $cmd = "my \$X=$ary[1]; if (ref(\$X) ne 'ARRAY') { \$X=[]; \$R->error_from(\"line $line_num_int at \$R->{__src_file}\", '[executor] $y: data is not array'); }; ";
				if ($localvar) {
					@$stack = ($cmd . "foreach $ary[0] (\@\$X, \x02[$begin])");
				} else {	# 通常変数
					@$stack = ($cmd . "foreach(\@\$X, \x02[$begin])\x02{ $ary[0]=\$_;}\x02");
				}
				@$stype = ('!*');
				$st->{last}=1;
				return;
			}

			if ($y eq 'foreach_hash') {
				my $cmd = "my \$H=$ary[1]; if (ref(\$H) ne 'HASH') { \$H={}; \$R->error_from(\"line $line_num_int at \$R->{__src_file}\", '[executor] $y: data is not hash'); };"
				. " my \$Keys=\$H->{_order} || [keys(\%\$H)];"
				. " foreach(\@\$Keys, \x02[$1])";
				# foreach(local(t,u), hash)  --> my($t,$u)
				# foreach(array(t,u), hash)  --> [$R->{t},$R->{u}]
				my $v = $ary[0];
				if ($v =~ /^my *\(\$\w+,\$\w+\)$/) {
					$cmd .= "\x02{$v = (\$_, \$H->{\$_});}\x02";
				} elsif ($v =~ /^\[([^,]+,[^,]+)\]$/) {
					$cmd .= "\x02{($1) = (\$_, \$H->{\$_});}\x02";
				} else {
					$cmd .= "\x02{$ary[0] = {key=>\$_, val=>\$H->{\$_}};}\x02";
				}
				@$stack = ($cmd);
				@$stype = ('!*');
				$st->{last}=1;
				return;
			}

			if ($y =~ /^foreach_(keys|values)$/) {
				my $type = $1;
				my $cmd  = "my \$H=$ary[1]; if (ref(\$H) ne 'HASH') { \$H={}; \$R->error_from(\"line $line_num_int at \$R->{__src_file}\", '[executor] $y: data is not hash'); };";
				my $ary  = ($type eq 'keys' ? "\$H->{_order} ? \@{\$H->{_order}} : " : '') . "$type(\%\$H)";

				if ($localvar) {
					@$stack = ($cmd . "foreach $ary[0] ($ary, \x02[$begin])");
				} else {	# 通常変数
					@$stack = ($cmd . "foreach($ary, \x02[$begin])\x02{ $ary[0]=\$_;}\x02");
				}
				@$stype = ('!*');
				$st->{last}=1;
				return;
			}

			if ($y eq 'foreach_num') {
				$ary[1] =~ s/^\((.*)\)$/$1/;
				if ($localvar) {
					@$stack = ("foreach $ary[0] (1..int($ary[1]), \x02[$begin])");
				} else {
					@$stack = ("foreach(1..int($ary[1]), \x02[$begin])\x02{ $ary[0]=\$_;}\x02");
				}
				@$stype = ('!*');
				$st->{last}=1;
				return;
			}
		}
		if ($#ary == 3 && $ary[3] =~ /^\x01\[(begin.*)\]$/) {
			my $begin = $1;
			if ($y eq 'foreach_num') {
				$ary[1] =~ s/^\((.*)\)$/$1/;
				$ary[2] =~ s/^\((.*)\)$/$1/;
				if ($localvar) {
					@$stack = ("foreach $ary[0] (int($ary[1])..int($ary[2]), \x02[$begin])");
				} else {
					@$stack = ("foreach(int($ary[1])..int($ary[2]), \x02[$begin])\x02{ $ary[0]=\$_;}\x02");
				}
				@$stype = ('!*');
				$st->{last}=1;
				return;
			}
		}
	}

	#-----------------------------------------------------------------------
	# ifxxx の inline 展開
	#-----------------------------------------------------------------------
	if ($InlineIf{$y}) {
		$self->set_check_break_ifneed($st->{l_info}, $y);

		my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		$x = undef;
		if ($y eq 'ifdef') {
			$y = 'if';
			$ary[0] = "defined($ary[0])";
		}
		if ($y eq 'if' && $st->{last_op} && $#ary == 1 && $st->{cmd_flag} eq '@') {
			$self->set_no_change($st->{l_info});
			$x = "($ary[0] && ($VAR_OUT.=($ary[1])));";

		} elsif ($y eq 'if' && $ary[1] eq '') {
			$x = undef;	# error
		} elsif ($y eq 'if') {
			if ($ary[2] ne '') {
				$x = "($ary[0] ? $ary[1] : $ary[2])";
			} else {
				$x = "($ary[0] && $ary[1] || undef)";
			}
		} elsif ($y eq 'ifset') {
			if ($#ary > 2) {
				$x = "($ary[1]=$ary[0] ? $ary[2]: $ary[3])";
			} elsif ($#ary == 2) {
				$x = "($ary[0] && ($ary[1]=$ary[2]))";
			} else { $x=undef; }
		} elsif ($y =~ /^if(next|last)$/) {	# ifnext / iflast
			if ($#ary == 0) {
				$x = "($ary[0] && $1)";
			} else { $x=undef; }
		} elsif ($InlineIf{$y} == 3 || $InlineIf{$y} == 4) {	# ifpush / ifpop
			my $cond = shift(@ary);
			my $func = substr($y, 2);	# iffunc → func
			if ($InlineIf{$y}==4) { $ary[0] = '@{' . $ary[0] . '}'; }
			$x = join(',', @ary);
			$x = "($cond && $func($x))";
		} elsif (substr($y,0,2) eq 'if') {
			$self->set_need_line_num($st->{l_info});
			my $func = substr($y, 2);	# iffunc → func
			if ($BuiltinFunc{$func}) {
				$self->set_check_break_ifneed($st->{l_info}, $func);
				$func = "\x04$func";
			} else {
				$func = "\$R->$func";
			}
			$x = shift(@ary);

			if ($InlineIf{$y} == 2 && $ary[1] ne '') {	# ifxxx(exp, A, B)
				$x = "$func($x ? $ary[0] : $ary[1])";
			} elsif ($st->{last_op} && $st->{cmd_flag} eq '@') {
				$self->set_no_change($st->{l_info});
				$x = "($x && ($VAR_OUT.=$func(" . join(',', @ary) . ")));";
			} else {
				$x = "($x && $func(" . join(',', @ary) . "))";
			}
		}
		if (!defined $x) {
			$st->{error}=1;
			return;
		}
		push(@$stack, $x);
		push(@$stype, '!*');
		return;
	}

	#-----------------------------------------------------------------------
	# core関数呼び出し
	#-----------------------------------------------------------------------
	if (exists $CoreFuncs{$y}) {
		$self->set_need_line_num($st->{l_info});

		# perl core 関数の呼び出し
		if ($x eq '' || $x eq 'undef') {	# 引数省略は許可しない
			if ($CoreFuncs{$y}==-1) {	# next/last等の裸制御文
				push(@$stack, $y);
				push(@$stype, '!*');
				$st->{last}=1;
				return;
			}
			push(@$stack, $x,  $y);
			push(@$stype, $xt, $yt);
			$st->{error}=1;
			return;
		}

		# bit 0 =  1 : 戻り値が array
		# bit 1 =  2 : 第１引数が array
		# bit 2 =  4 : 第２引数が array
		# bit 3 =  8 : 第３引数が array
		my $mode = $CoreFuncs{$y};
		if ($mode) {
			my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
			foreach(0..6) {
				if ($mode & (2<<$_) && defined $ary[$_]) { $ary[$_] = '@{' . $ary[$_] . '}'; }
			}
			if ($mode &  256 && defined $ary[0]) { $ary[0] = '%{' . $ary[0] . '}'; }
			if ($mode &  512 && defined $ary[1]) { $ary[1] = '%{' . $ary[1] . '}'; }
			if ($mode & 1024 && defined $ary[2]) { $ary[2] = '%{' . $ary[2] . '}'; }
			$x = join(',', @ary);
		}
		$x =~ s/^\((.*)\)$/$1/;	# 一番外の (  ) を外す

		if ($CoreFuncs{$y} & 1) {
			push(@$stack, "[ $y($x) ]");	# 配列の戻り値をreference化
		} else {
			push(@$stack, "$y($x)");
		}
		push(@$stype, '!*');
		return;
	}

	#-----------------------------------------------------------------------
	# inline関数呼び出し
	#-----------------------------------------------------------------------
	if (exists $InlineFuncs{$y}) {
		my $err;
		my $func = $InlineFuncs{$y};
		my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		$func =~ s/#(\d)/
			$err |= ($ary[$1] eq '' || $ary[$1] eq 'undef');
			$ary[$1]
		/eg;

		if ($err) {	# 必要な引数がない
			push(@$stack, $x,  $y);
			push(@$stype, $xt, $yt);
			$st->{error}=1;
			return;
		}
		push(@$stack, "($func)");
		push(@$stype, '!*');
		return;
	}

	#-----------------------------------------------------------------------
	# その他の関数呼び出し
	#-----------------------------------------------------------------------
	$self->set_need_line_num($st->{l_info});

	if ($y eq 'array') {
		# array (a, b, c, ...) to [a, b, c]
		# arrayq(a, b, c, ...) to ['a', 'b', 'c']
		my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		$x = join(',', @ary);
		push(@$stack, "[$x]");

	} elsif ($y eq 'hash' || $y eq 'hashx') {
		# hash (a1, b1, a2, b2, ...) to {a1=>b1, a2=>b2}
		# hashq(a1, b1, a2, b2, ...) to {'a1'=>'b1', 'a2'=>'b2'}
		#      {a1, b1, a2, b2, ...} to {'a1'=>b1, 'a2'=>b2}	// = hashx()
		my @ary;
		if ($y eq 'hash') {
			@ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		} else {
			my @a = $self->array2quote_string(ref($x_orig) ? @$x_orig : $x_orig);
			my @b = $self->get_objects_array($x_orig, $xt, $local_vars);
			foreach(0..$#a) {
				push(@ary, (($_ & 1) ? $b[$_] : $a[$_]));
			}
		}
		my $x='';
		@ary = grep { $_ ne '' } @ary;
		while(@ary) {
			my $a=shift(@ary);
			my $b=shift(@ary) || '';
			$x .= "$a=>$b,";
		}
		chop($x);
		push(@$stack, "{$x}");

	} elsif ($y eq 'flag') {
		# flag (a, b, c, ...) to {a=>1, b=>1, ...}
		# flagq(a, b, c, ...) to {'a'=>1, 'b'=>1, ...}
		my @ary = $self->get_objects_array($x_orig, $xt, $local_vars);
		@ary = grep { $_ ne '' } @ary;
		if (@ary) {
			$x = "{" . join('=>1,', @ary) . "=>1}";
		} else {
			$x='{}';
		}
		push(@$stack, $x);

	} elsif ($BuiltinFunc{$y}) {
		$self->set_check_break_ifneed($st->{l_info}, $y);
		push(@$stack, "\x04$y($x)");
	} elsif ($yt eq 'obj') {
		$self->set_check_break_ifneed($st->{l_info}, $y);
		my ($class, $func) = $self->get_object_sep($y,$local_vars);
		if ($func =~ /^'/) {
			$st->{error_msg} = 'illegal function name';
			return;
		}
		push(@$stack, "$class\-\>$func($x)");
	} elsif ($yt eq 'function-name') {		# %h 記述参照のこと
		$self->set_check_break_ifneed($st->{l_info}, $y);
		push(@$stack, "$y($x)");
	} else {	# エラー
		push(@$stack, $x,  $y);
		push(@$stype, $xt, $yt);
		$st->{error}=1;
		return;
	}
	push(@$stype, '!*');
	return;
}

#-------------------------------------------------------------------------------
# ○行情報設定
#-------------------------------------------------------------------------------
sub set_check_break_ifneed {
	my $self = shift;
	if ($self->check_break_function($_[1])) {
		$_[0] |= $L_break_check
	}
	return $_[0];
}
sub set_need_line_num {		# ソース行情報を持つ
	my $self = shift;
	return ($_[0] |= $L_line_number);
}
sub set_no_change {		# 加工禁止
	my $self = shift;
	return ($_[0] |= $L_no_change);
}

#-------------------------------------------------------------------------------
# ○要素の種類を取得
#-------------------------------------------------------------------------------
sub get_element_type {
	my $self     = shift;
	my $constant = shift;
	my $lv_stack = shift;
	my $strbuf   = shift;

	my $p = $_[0];
	if (exists $OPR{$p}) { return 'op'; }	# 演算子
	if ($p =~ /^\x01(\d+)\x01$/) {			# 文字列
		# 該当文字列を評価する
		my $num = $1;
		my $local_vars = $lv_stack->[ $#$lv_stack ];
		$strbuf->[$num] =~ s/\x01<([^>]+?)\#(\d+)>/$self->get_object($1, $local_vars) . "->[$2]"/eg;
		$strbuf->[$num] =~ s!\x01<([^>]+?)>!
			if (exists $constant->{$1}) {
				my $c = $constant->{$1};
				if ($c =~ /^\x01(\d+)\x01$/ && $strbuf->[$1] =~ /^\'(.*)\'$/) {
					$c = $1;
					$c =~ s/\\([\\\'])/$1 eq "'" ? "'" : "\\"/eg;
					$c =~ s/([\"\\\$\@])/"\\$1"/eg;
				}
				$c;
			} else {
				$self->get_object($1,$local_vars,1);
			}
		!eg;
		return substr($strbuf->[$num],0,1) eq "'" ? 'const' : 'string';
	}
	if ($p =~ /^'[^\']*'$/) {		# 文字定数
		return 'const';
	}
	if ($p =~ /^([\d\.]+)([KMGT]|week|day|hour|min|sec)B?$/) {	# 単位付き数値
		$p *= $Unit2Num{$2};
		$_[0] = int($p);
		return 'const';
	}
	if ($p =~ /[^\w\.]/)   { return 'error'; }	# 不正な文字列／エラー
	if ($p =~ /^[\d\.]+$/) { return 'const'; }	# 数値（加工しない）
	if ($p =~ /^0[xb][\dA-Fa-f]+$/) { return 'const'; }		# 2進数 16進数
	if ($p =~ /^([\d\.]+)([KMGT]|week|day|hour|min|sec)B?$/) {	# 単位付き数値
		$p *= $Unit2Num{$2};
		$_[0] = int($p);
		return 'const';
	}
	if ($p =~ /^(\d+)\.\w+$/) {		# 説明付きの数値  10.is_cache_on など
		$_[0] = $1; return 'const';
	}
	if ($p =~ /^begin(_?\w+)?(|\.\w+)$/) {		# block
		$_[0] = "\x01[$p]";
		if ($p =~ /^begin_array/) {
			return 'array';
		}
		if ($p =~ /^begin_hash/) {
			return 'hash';
		}
		if ($p =~ /^begin_string/) {
			return 'string';
		}
		if ($p !~ /^begin_/) {
			my %h = %{ $lv_stack->[ $#$lv_stack ] };
			push(@$lv_stack, \%h);
		}
		return 'block';
	}
	if ($p =~ /^end(_?\w+)?(|\.\w+)$/ || $p =~ /^else()(|\.\w+)$/) {
		if (!$1 && $#$lv_stack) {
			pop(@$lv_stack);
		}
		$_[0] = $p; return 'block';
	}
	if ($p =~ /^yes$/i || $p =~ /^true$/i) {
		$_[0] = 1; return 'const';
	}
	if ($p =~ /^no$/i || $p =~ /^false$/i) {
		$_[0] = 0; return 'const';
	}
	if ($p =~ /^new(|\..*)$/) {
		if ($1 eq '' || $1 eq '.hash') { $_[0] = '{}'; return 'hash';  }
		if ($1 eq '.array')            { $_[0] = '[]'; return 'array'; }
		$_[0] = ''; return 'error';
	}
	if ($p eq 'undef') { return 'const'; }
	if ($p eq '__undef__') { $_[0]=''; return 'const'; }
	if (exists $constant->{$p}) { $_[0] = $constant->{$p}; return 'const'; }

	return 'obj';
}

#///////////////////////////////////////////////////////////////////////////////
# ●[05] begin - end ブロックの取り出しと文字列の置換
#///////////////////////////////////////////////////////////////////////////////
sub split_begin_block {
	my ($self, $buf, $local_var_tmp_ary) = @_;

	# 処理ループ
	my $line = 0;		# 行カウンタ
	my @arybuf = ([]);	# 先頭に dummy を積む
	my @newbuf;
	while(@$buf) {
		$line++;
		my $line = shift(@$buf);
		# begin ブロックの切り出し
		if (ord($line) == 1 && $line =~ /[\x01\x02]\[begin.*?\]/) {
			unshift(@$buf, $line);
			$self->split_begin(\@newbuf, $buf, \@arybuf);
			next;
		}
		push(@newbuf, $line);
	}
	# end/elsif が残ってないか確認する（エラーチェック）
	foreach my $ary (\@newbuf,@arybuf) {
		foreach(@$ary) {
			if ($_ =~ /^\x01\d+(else|end|elsif)(?:\.([^#]*))?/) {
				my $cmd  = $1;
				my $lnum = $self->get_line_num_int($_);
				my $line = $self->tag_escape( $self->get_line_data($_) );
				$self->error($lnum, "Exists '%s' without 'begin': %s", $cmd, $line);
				$_ = "<!-- compiler : block '$cmd' exists, but corresponding 'begin' does not exist: $line -->";
			}
		}
	}
	# arybuf先頭に実行文本体を入れる
	$arybuf[0] = \@newbuf;

	return \@arybuf;
}

sub get_line_num {
	my $self = shift;
	return substr($_[0], 1, $LineNumLen);
}
sub get_line_num_int {
	my $self = shift;
	return int(substr($_[0], 1, $LineNumLen));
}
sub get_line_data {
	my $self = shift;
	return substr($_[0], 1+$LineNumLen);
}

#-----------------------------------------------------------
# ○begin block 処理メイン（再起対応）
#-----------------------------------------------------------
sub split_begin {
	my ($self, $newbuf, $buf, $arybuf) = @_;

	my @if_blocks;
	my $info = 0;
	my $t = shift(@$buf);
	if ($t =~ /(.*?)\#(\d+)$/s) { $t=$1; $info=$2; }

	my $first=1;
	while (ord($t) == 1 && $t =~ /(.*?)([\x01\x02])\[(begin(_\w+)?(\.\w+)?)\](.*)/s) {
		my $left  = $1;
		my $flag  = $2;
		my $begin = $3;
		my $type  = $4;
		my $label = $5;
		my $right = $6;

		my $ary = $self->splice_block($buf, $type, $label, $arybuf);
		if (! defined $ary) {
			my $lnum = $self->get_line_num_int($t);
			$self->error($lnum, "'%s' without 'end'", $begin);
			$t = "<!-- compiler : '$begin' without 'end' -->";
			last;
		}
		if ($ary->[$#$ary] =~ /^\x01\d+elsif\(/) {
			$right = ",$flag\[$begin\]" . $right;
			my $elsif = pop(@$ary);
			$elsif    =~ s/^(\x01\d+)elsif\(/$1}elsif(/;
			unshift(@$buf, $elsif);
		}

 		# 前処理
		if ($type eq '_string' || $type eq '_array' || $type eq '_hash' || $type eq '_hash_order') {
			my @newary;
			my $line = [];
			foreach(@$ary) {
				push(@$line, $_);
				my $flag = ord($_);
				if ($flag>3 && ($_ =~ /[\r\n]$/)) {
					push(@newary, $line);
					$line = [];
				}
			}
			if (@$line) { push(@newary, $line); }
			# 最初や最後が空白だけの行なら除去
			if (@newary) {
				my $x = $newary[0];
				if ($#$x == 0 && $x->[0] =~ /^[\s\r\n]*$/) { shift(@newary); }
				my $y = $newary[$#newary];
				if ($#$y == 0 && $y->[0] =~ /^[\s\r\n]*$/) { pop(@newary);   }
			}
			$ary = \@newary;
		}

		# 各行の行頭、行末スペースと改行を消去
		if ($type eq '_array' || $type eq '_hash' || $type eq '_hash_order') {
			foreach(@$ary) {
				while(@$_ && $_->[0] =~ /^\s*$/) {
					shift(@$_);
				}
				$_->[0] =~ s/^\s*//;

				# 行末
				my $flag = @$_ && ord($_->[$#$_]) || 0;
				if ($flag>3){
					$_->[$#$_] =~ s/[\r\n]*$//;
				}
				while(@$_ && $_->[$#$_] =~ /^\s*$/) {
					pop(@$_);
				}
				if ($flag>3){
					$_->[$#$_] =~ s/\s*$//;
				}
			}
		}

		if ($type eq '_string') {
			my @ary2;
			foreach(@$ary) {
				push(@ary2, @$_);
			}
			$ary = $self->chain_lines(\@ary2);

		} elsif ($type eq '_array') {
			foreach(@$ary) {
				$_ = $self->chain_lines($_);
			}
			$ary = '[' . join(',', @$ary) . ']';
			$ary =~ s/[\x01-\x03]//g;

		} elsif ($type eq '_hash' || $type eq '_hash_order') {
			my %hash;
			if ($type eq '_hash_order') { $hash{_order}=1; }
			my @order;	# key順序保存配列
			my $order_ng;	# 順序保持不可フラグ
			my @out;
			foreach my $line (@$ary) {
				# xx = yyyy の = の位置を特定する
				my @key;
				my @val;
				foreach(0..$#$line) {
					my $x = $line->[$_];
					if (ord($x)<4) { next; }
					if ($x !~ /^(.*?)\s*=\s*(.*)/) { next; }
					# = 発見
					@val = splice(@$line, $_+1);	# 順次変更不可！
					@key = splice(@$line, 0, $_);
					if ($2 ne '') { unshift(@val, $2); }
					if ($1 ne '') {    push(@key, $1); }
					last;
				}
				if (!@key) {
					if (join('',@$line) ne '') {
						my $lnum = $self->get_line_num($t);
						$self->warning($lnum, "Contaion line is not defined hash in '%s'", $begin);
						$self->warning($lnum, "-->" . join('',@$line));
					}
					next;
				}

				my $is_string = 1;
				foreach(@key) {
					if (ord($_)>3) { next; }
					$is_string = 0;
					last;
				}
				if ($is_string) {
					# key が文字列でのみ構成されている。
					my $key = join('',@key);
					my $val = $self->chain_lines(\@val);
					if (exists $hash{$key}) {
						my $lnum = $self->get_line_num($t);
						$self->warning($lnum, "Dupulicate Hash key '%s' in '%s'", $key, $begin);
					}
					$hash{$key} = $val;
					if ($key eq '_order') { next; }

					$self->into_single_quot_string($key);
					push(@order, $key);		# 順番保持用
					push(@out, "$key=>$val");	# 出力
					next;

				}
				# key部に変数やコマンドが含まれる
				$order_ng = 1;
				my $key = $self->chain_lines(\@key);
				my $val = $self->chain_lines(\@val);
				push(@out, "$key=>$val");	# 出力
			}
			# ハッシュ定義として整形する
			if ($hash{_order}) {
				if ($order_ng) {
					my $lnum = $self->get_line_num($t);
					$self->warning($lnum, "Don't use ordering hash (contaion variable key) in '%s'", $begin);
				} else {
					my $ord = join(',',@order);
					push(@out, "_order=>[$ord]");	# 出力
				}
			}
			$ary = '{' . join(',', @out) . '}';

		} elsif ($type eq '' && $flag eq "\x02") {	# 実行構文のブロック展開
			push(@if_blocks, $ary);
			if ($left =~ /(.*?),\s*$/s) { $left = $1; }	# , より手前
			$t = $left . $right;
			$ary='';

		} elsif ($type eq '') {				# 実行構文（無名関数）
			push(@$arybuf, $ary);
			$ary = "\x04[$#$arybuf]\x04";

		} else {		# 未知のbegin
			my $lnum = $self->get_line_num($t);
			$self->error($lnum, "Unknown begin type (%s)", $begin );
			$t = "<!-- compiler : Unknown begin type ($begin) -->";	# エラー行を置換
			last;
		}
		$t = $left . $ary . $right;
		## print $_, "\n";
	}
	#-------------------------------------------------------------
	# ○ブロック展開処理
	#-------------------------------------------------------------
	if (@if_blocks) {
		$t =~ s/^(\x01\d+)ifexec\(/${1}if (/;
		if ($t =~ /\x02\{.*?\}\x02/) {
			$t =~ s/\x02\{(.*?)\}\x02//g;
			push(@$newbuf, "$t {$1#$L_no_change");
		} else {
			push(@$newbuf, "$t {#$L_no_change");
		}
		my $block = shift(@if_blocks);
		$self->info_rewrite($block, $info & $L_replace);
		push(@$newbuf, @$block);
		# else ?
		while (@if_blocks) {
			$block = shift(@if_blocks);
			if ($block->[0] =~ /^\x01(\d+)}elsif\((.*)\)/) {
				push(@$newbuf, "\x01$1} elsif ($2) {#$L_no_change");
				shift(@$block);
			} else {
				push(@$newbuf, "\x01$LineNumZero} else {#$L_no_change");
			}
			$self->info_rewrite($block, $info & $L_replace);
			push(@$newbuf, @$block);
		}
		push(@$newbuf, "\x01$LineNumZero}#$L_no_change");
		return ;
	}
	$t .= "#$info";
	push(@$newbuf, $t);
}

#-----------------------------------------------------------
# ○ブロックの取り出し, split_begin と対
#-----------------------------------------------------------
sub splice_block {
	my $self = shift;
	my ($buf, $type, $label, $arybuf) = @_;
	my @ary;
	while(@$buf) {
		my $line = shift(@$buf);
		if ($line =~ /^\x01\d+(?:else|end)(_\w+)?(\.\w+)?/
		 && ($1 eq '' || $1 eq $type) && $2 eq $label) {
			return \@ary;
		}
		if ($line =~ /^\x01\d+elsif\(.*/) {
			push(@ary, $line);
			return \@ary;
		}
		if (ord($line) == 1 && $line =~ /[\x01\x02]\[begin.*?\]/) {
			unshift(@$buf, $line);
			$self->split_begin(\@ary, $buf, $arybuf);
			next;
		}
		if ($line ne '') {
			push(@ary, $line);
		}
	}
	return undef;		# ブロックの終わりが見つからない
}

#-----------------------------------------------------------
# ○ブロックの行情報書き換え
#-----------------------------------------------------------
sub info_rewrite {
	my $self = shift;
	my ($block, $replace) = @_;
	foreach(@$block) {
		if (ord($_) != 1) {
			if (!$replace) { $_=''; }
			next;
		}
		my $info;
		if ($_ =~ /(.*?)\#(\d+)$/s) { $_=$1; $info=$2; }
		if (!$replace) { $info &= (0x7fffffff - $L_replace); }
		$info += $L_indent;
		$_ .= "#$info";
	}
}


#-----------------------------------------------------------
# ○複数行を一つのperl式にまとめる
#-----------------------------------------------------------
sub chain_lines {
	my $self = shift;
	my $ary  = shift;
	my @ary2;
	my $chain = 0;
	# 非コマンド行の連続を連結する
	foreach(@$ary) {
		if (ord($_) < 4) {
			push(@ary2, $_);
			$chain = 0;
			next;
		}
		if ($chain) {
			$ary2[$#ary2] .= $_;
		} else {
			push(@ary2, $_);
		}
		$chain = 1;
	}

	my @ary3;
	foreach(@ary2) {
		my ($flag, $info, $cmd) = $self->parse_line_to_cmd( $_ );
		if ($flag == 1) {	# cmd
			if (!($info & $L_replace)) {	# 置換しない
				$cmd = "('',$cmd)[0]";
			}
			if (!($info & $L_const)) {	# 定数ではない
				$cmd = "($cmd)";
			}
		}
		if ($flag>3 && substr($cmd,0,1) ne "'" && $#ary2>0) {
			# single quote されてなかったら（数値等）quote する
			$cmd = "'$cmd'";
		}
		push(@ary3, $cmd);
	}
	return @ary3 ? join('.', @ary3) : "''";
}

#///////////////////////////////////////////////////////////////////////////////
# ●[06] 不要な行を削除し、行をまとめる
#///////////////////////////////////////////////////////////////////////////////
sub optimize {
	my ($self, $arybuf) = @_;

	my $pragma = $self->{pragma};			# プラグマロード
	foreach my $ary (@$arybuf) {
		my @new_ary = ('dummy');		# 処理の都合で、積んでおく
		my $str;
		foreach (@$ary) {
			my $f = ord($_);
			if ($_ eq '' || $f > 3) {	# 普通の文
				$str .= $_;
				next;
			}
			#
			# コマンド or 置換文
			#
			if($str ne '') {
				if (~$pragma & $P_cmd_only) { push(@new_ary, $str); }
				$str = '';
			}
			push(@new_ary, $_);
		}
		shift(@new_ary);	# dummy を読み捨て
		if ($str ne '' && (~$pragma & $P_cmd_only)) { push(@new_ary, $str); }
		$ary = \@new_ary;
	}
	return $arybuf;
}

#///////////////////////////////////////////////////////////////////////////////
# ●[07] arrayブロックを１つのサブルーチンに置き換える
#///////////////////////////////////////////////////////////////////////////////
# inline 関数を展開する。
sub array2sub {
	my ($self, $arybuf) = @_;
	my $pragma = $self->{pragma};

	my @BuiltinFuncs;
	my %BuiltinFuncs_cache;
	my $is_main = 1;
	my $is_function = $pragma & $P_is_function;
	foreach my $ary (@$arybuf) {
		my @sub_array;
		my $base_indent = "\t";
		if (! $is_main) {
			$base_indent = "\t\t";
			push(@sub_array, $SUB_HEAD);
			$sub_array[$#sub_array] =~ s/\n\t/\n\t\t/g;
		}
		# indent 処理
		my $indent = $base_indent;
		foreach(@$ary) {
			my ($flag, $info, $cmd) = $self->parse_line_to_cmd( $_ );
			# unknown
			if ($flag == 0) { next; }
			# そのまま出力
			if ($flag > 1) {
				# xxx.yy.zz 形式のデータに置換
				# xxx.yy.zz 形式で xx がローカル変数
				# コマンド外文字列
				push(@sub_array, $indent . "$VAR_OUT.=$cmd;\n");
				next;
			}
			#-------------------------
			# $flag==1 コマンド行
			#-------------------------
			# indent 処理
			$indent = $base_indent . ("\t" x ($info >> $L_indent_bits));

			# 行番号
			my $lnum = $self->get_line_num_int($_);

			# 加工禁止
			if ($info & $L_no_change) {
				push(@sub_array, "$indent$cmd\n");
				if ($cmd =~ /^if\s*\(.*\)\s*\{/ || $cmd =~ /^}\s*else\s*\{/ || $cmd =~ /^}\s*elsif\s*\(.*\)\s*\{/ || $cmd =~ /^my \$[XH]/ || $cmd =~ /^foreach /) { $indent .= "\t"; }
				next;		# $cmd =~ /^my \$[XH]/ は foreach/foreach_hash のため
			}
			# 置換処理
			if (!$is_function && $info & $L_replace) {	# 置換
				if ($cmd =~ /;,/) { $cmd = "$VAR_OUT.=do{ $cmd };"; }
				             else { $cmd = "$VAR_OUT.=$cmd;"; }
			} else {
				$cmd .= ';';
			}

			# 行番号が必要？（エラーが起こらない行では不要）
			if ($info & $L_line_number) { $cmd  = "$VAR_LNUM=$lnum; " . $cmd; }
			# break flag を確認？
			if ($info & $L_break_check) { $cmd .= " \$R->{Break} && return;"; }
			# コマンドを出力
			push(@sub_array, "$indent$cmd\n");
		}
		if ($is_function) {	# 関数処理なら最後にreturnする
			push(@sub_array, "\treturn;\n");
		}
		push(@sub_array, $is_main ? "}\n" : "\t}\n");
		$ary = join('', @sub_array);

		$is_main=0;
	}

	#-------------------------------------------------------------
	# arrray buf を1つの関数に納める
	#-------------------------------------------------------------
	my $main = shift(@$arybuf);
	foreach(@$arybuf) {
		chomp( $arybuf->[($1-1)] );
		$main =~ s/\x04\[(\d+)\]\x04/$arybuf->[($1-1)]/eg;
	}
	my $subs = '';
	my $use_funcs = $self->{use_builtin_ary};
	foreach (@$use_funcs) {
		chomp($_);
		$_ = "push(\@F, $_);\n";
		$subs .= $_;
	}
	if ($subs ne '') { $subs = "\tmy \@F;\n" . $subs; }

	my $append='';
	if ($pragma & $P_is_function) {
		# 関数処理ならば、それを Base.pm に通知する
		$append .= "\t\$R->{IsFunction}=1;\n";
	}
	return [$SUB_HEAD . $append . $subs . $main];
}

#-----------------------------------------------------------
# 行情報からのPerl実行形式に変換する
#-----------------------------------------------------------
sub parse_line_to_cmd {
	my $self = shift;
	my $line = shift;
	my $use_builtin_ary  = $self->{use_builtin_ary};
	my $use_builtin_hash = $self->{use_builtin_hash};

	my $flag = ord($line);
	my $info = 0;

	# そのまま出力
	if ($flag > 3) {
		$self->into_single_quot_string($line);
		return ($flag, $info, $line);
	}
	# xxx.yy.zz 形式のデータに置換
	if ($flag == 2) {
		my $obj = $self->get_object( substr($line, 1) );
		return ($flag, $info, $obj);
	}
	# xxx.yy.zz 形式で xx がローカル変数
	if ($flag == 3) {
		$line =~ /^\x03((\w+).*)$/;
		my $obj = $self->get_object( $1, {$2 => 1} );
		return ($flag, $info, $obj);
	}

	# unknown
	if ($flag == 0) { return ($flag, 0, ''); }

	#-------------------------------
	# 実行式 ($flag = 1)
	#-------------------------------
	my $cmd = $self->get_line_data($line);

	# 行情報分離
	if ($cmd =~ /(.*?)\#(\d+)$/s) {
		$cmd  = $1;	# コマンド
		$info = $2;	# 行情報
	}

	# 組み込み関数?
	$cmd =~ s!\x04(\w+)\(!
		my $arg = $BuiltinFunc{"$1.arg"};
		if (exists($use_builtin_hash->{$1})) {
			'&{$F[' . $use_builtin_hash->{$1} . ']}(' . $arg;
		} else {
			# 初めて使用する組み込み関数
			push(@$use_builtin_ary, $BuiltinFunc{$1});
			$use_builtin_hash->{$1} = $#$use_builtin_ary;
			'&{$F[' . $#$use_builtin_ary . ']}(' . $arg;
		}
	!eg;
	return ($flag, $info, $cmd);
}



#///////////////////////////////////////////////////////////////////////////////
# ●[08] 文字列を復元する
#///////////////////////////////////////////////////////////////////////////////
sub recover_string {
	my ($self, $arybuf, $strbuf) = @_;

	foreach my $ary (@$arybuf) {
		if (! ref($ary)) {
			$ary =~ s/\x01(\d+)\x01/$strbuf->[$1]/g;
			next;
		}
		foreach(@$ary) {
			$_ =~ s/\x01(\d+)\x01/$strbuf->[$1]/g;
		}
	}
	return $arybuf;
}


################################################################################
# ■エラー処理
################################################################################
sub error {
	my $self = shift;
	my $line = shift;
	my $ROBJ = $self->{ROBJ};
	$self->{errors}++;
	if ($line) { $line=" at line " . int($line); }
	$ROBJ->error("[Compiler] $self->{src_file}$line : " . $ROBJ->translate(@_));
}
sub warning {
	my $self = shift;
	my $line = shift;
	my $ROBJ = $self->{ROBJ};
	$self->{warnings}++;
	if ($line) { $line=" at line " . int($line); }
	$ROBJ->warning("[Compiler] $self->{src_file}$line : " . $ROBJ->translate(@_));
}

sub debug {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $msg  = "[Compiler] $self->{src_file} : " . join(' ', @_);
	return $ROBJ->_debug($msg);	# debug-safe
}

################################################################################
# ■サブルーチン
################################################################################
#-------------------------------------------------------------------------------
# ●名前からオブジェクトの取得
#-------------------------------------------------------------------------------
sub get_object {
	my $self = shift;
	my ($name, $local_vars, $in_string) = @_;
	$local_vars ||= {};
	if ($name eq 'v')         { return '$v'; }
	if ($local_vars->{$name}) { return $in_string?"\${$name}":"\$$name"; }
	my ($class, $name) = $self->get_object_sep(@_);
	return "$class\-\>{$name}";
}

sub get_object_sep {
	my $self  = shift;			# ■■注意■■ この仕様を変更する場合は、
	my $name  = shift;			# convert_reversed_poland も必ず変更すること。
	my $local_vars = shift || {};
	$name =~ s/[^\w\.]//g;			# 半角英数と _ . 以外の文字を除去
	if ($name eq '') { return 'undef'; }	# エラー時未定義を示すオブジェクトを返す

	$name =~ s/\.(\.*)/#$1/g;
	my @ary = split(/#/, $name);
	my $obj  = "\$R";

	my $first = $ary[0];
	if ($first eq 'v')              { $obj='$v';       shift(@ary); }
	  elsif ($local_vars->{$first}) { $obj="\$$first"; shift(@ary); }
	# print "$first $obj $local_vars->{$first}\n";

	@ary = map {
		(index($_, '.')>=0 || $_ =~ /^\d/) ? "'$_'" : $_
	} @ary;

	my $last = pop(@ary);
	foreach(@ary) {
		$obj .= "->{$_}";
	}
	return ($obj, $last);
}

sub get_objects_array {
	my $self  = shift;
	my $names = shift;
	my $types = shift;
	if (!ref $names) { $names = [$names]; }
	if (!ref $types) { $types = [$types]; }

	my @ary;
	foreach(0..$#$names) {
		my $name = $names->[$_];
		my $type = $types->[$_];
		if ($type eq 'obj' || $type eq 'const_var') {
			$name = $self->get_object($name, @_);
		}
		push(@ary, $name);
	}
	return @ary;
}

sub array2quote_string {
	my $self = shift;
	my @ary;
	foreach(@_) {
		my $x = $_;
		$x =~ s/\\/\\\\/g;
		$x =~ s/'/\\'/g;
		push(@ary, $x);
	}
	return @ary;
}

#-------------------------------------------------------------------------------
# ●'' 中に入った文字列として加工する
#-------------------------------------------------------------------------------
sub into_single_quot_string {
	my $self = shift;
	foreach(@_) {
		if ($_ =~ /^[1-9]\d+$/) { next; }	# 1234
		if ($_ =~ /^\d+\.\d*$/) { next; }	# 12.34
		$_ =~ s/([\\'])/\\$1/g;
		$_ = "'$_'";
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●タグ除去
#-------------------------------------------------------------------------------
sub tag_escape {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/"/&quot;/g;
		$_ =~ s/>/&gt;/g;
		$_ =~ s/</&lt;/g;
	}
	return $_[0];
}

#-------------------------------------------------------------------------------
# ●break判定が必要な関数か？
#-------------------------------------------------------------------------------
# Ret) 1:true 0:false
my %break_function_cache;
sub check_break_function {
	my $self = shift;
	my $func = shift;
	if (exists $break_function_cache{$func}) {
		return $break_function_cache{$func};
	}

	my $flag=0;
	foreach(@BreakFuncs) {
		if (index($func,$_) == -1) { next; }
		$flag=1;
		last;
	}
	return ($break_function_cache{$func} = $flag)
}



################################################################################
# ■デバッガ
################################################################################
sub debug_save {
	my $self = shift;
	my ($filename, $buf, $lnum, $strbuf, $arybuf) = @_;
	my $ROBJ = $self->{ROBJ};
	my @lines;

	#---------------------------------------------------
	# 表示形式に変換
	#---------------------------------------------------
	if (ref $buf eq 'ARRAY') {
		@lines = @$buf;
		$self->conv_display_style(\@lines, $lnum);
	}

	#---------------------------------------------------
	# 表示形式に変換
	#---------------------------------------------------
	if (ref $arybuf) {
		my $no = 0;
		foreach my $ary (@$arybuf) {
			if ($no) { push(@lines, sprintf("\nARRAY:[%02d]", $no) . "--------------------------------------------------------------------\n"); }
			$no++;
			if (! ref($ary)) {	# 配列ではない
				push(@lines, $ary);
				next;
			}
			my @ary = @$ary;
			$self->conv_display_style(\@ary);
			foreach(@ary) {
				push(@lines, $_);
			}
		}
	}
	#---------------------------------------------------
	# 文字列復元
	#---------------------------------------------------
	foreach(@lines) {
		$_ =~ s/\x01(\d+?)\x01/$strbuf->[$1]/g;
		$_ =~ s/[\x00-\x04]//g;	# 制御文字除去
	}
	# save
	$ROBJ->fwrite_lines($filename, \@lines);
}

#-------------------------------------------------
# 表示用の加工処理
#-------------------------------------------------
sub conv_display_style {
	my $self = shift;
	my ($lines, $lnum) = @_;
	if (ref $lnum ne 'ARRAY') { $lnum = []; }

	my $line = 0;	# 行カウンタ
	my $this_line_default = '-' x $LineNumLen;
	foreach(@$lines) {
		$line++;
		my $s = '::';
		my $this_line = $this_line_default;
		if ($lnum->[$line]) { $this_line = sprintf("%0${LineNumLen}d", $lnum->[$line]); }
		if (ref $_ eq 'ARRAY') {	# 逆ポーランド記法の場合
			my @ary = @$_;
			$s = 'p)' . pop(@ary);
			$_ = join(' ', @ary);
		} elsif (ord($_) == 1) {	# eval - perl 式
			$s         = 'e$';
			$this_line = $self->get_line_num($_);	# 行番号取り出し
			$_         = $self->get_line_data($_);
			# 行情報取得
			my $info = 0;
			if ($_ =~ /\#(\d+)$/ && $1 & $L_replace) { $s = 'e@'; }
		} elsif (ord($_) == 2) {	# replace 単一式
			$s = 'R)';
			$_ = substr($_, 1);
		} elsif (ord($_) == 3) {	# replace 単一式 / ローカル変数
			$s = 'r)';
			$_ = substr($_, 1);
		}
		$_ =~ s/\n/\\n/g;	# 改行置換
		$_ =  "$this_line $s $_\n";
	}
}


1;