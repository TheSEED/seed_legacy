package SeedComponents::Basic;

use WebApplicationComponents qw(tabulator menu list table);
use HTML;

1;

sub get_blastresult {
  my ($params) = @_;

  # get options from params hash
  my $fig     = $params->{fig};
  my $tmpdir  = $params->{fig_temp};
  my $orgdir  = $params->{fig_organisms};
  my $ext_bin = $params->{fig_extbin};
  my $cgi     = $params->{cgi};
  my $seq     = $cgi->param("sequence");

  my $org = $cgi->param("genome");

  # initialize filename for sequence
  my $tmp_seq = "";
  my $html;

  # check for blast
  if ($cgi->param("blast_tool") =~ /blast/) {
    
    # initialize additional options
    my $add_options = "";

    # construct filename for sequence
    $tmp_seq = $tmpdir . "run_blast_tmp$$.seq";

    # create database filename string
    my $db = $orgdir;

    # check which blast was selected
    if (($cgi->param("blast_tool") eq "blastn") || ($cgi->param("blast_tool") eq "tblastn")) {
      $db .= "$org/contigs";
      
      # execute a format db
      if ((! -s "$db.nsq") || (-M "$db.nsq" > -M $db)) {
	system $ext_bin . "formatdb -p F -i $db";
      }

      if ($cgi->param("blast_tool") eq "blastn") {
	$add_options = "-r 1 -q -1 ";
      }
    } else {
      $db .= "$org/Features/peg/fasta";
      
      # execute a format db
      if ((! -s "$db.psq") || (-M "$db.psq" > -M $db)) {
	system $ext_bin . "formatdb -p T -i $db";
      }
    }

    # extend params hash with blast options
    $params->{program}       = $cgi->param("blast_tool");
    $params->{sequence_file} = $tmp_seq;
    $params->{database}      = $db;
    $params->{options}       = $cgi->param("blast_options");

    # strip sequence from whitespaces
    $seq =~ s/\s+//g;

    # write sequence to file
    open(SEQ, ">$tmp_seq") || die "run_blast could not open $tmp_seq";
    print SEQ ">query\n$seq\n";
    close(SEQ);
  
    # call blast
    if (($cgi->param("blast_tool") eq "blastn") or ($cgi->param("blast_tool") eq "tblastn")) {
      $params->{options} .= $add_options;
      @$html = execute_blastall($params);
    } else {
      @$html = map { &HTML::set_prot_links($cgi,$_) } execute_blastall($params);
    }

  # the tool must be either protein or dna scan
  } else {

    if ($org eq "") {
      return "You must select an organism.";
    }

    # construct filename for sequence
    $tmp_seq = $tmpdir . "tmp$$.pat";

    # initialize header variable
    my @out;
    my $col_hdrs;

    open(PAT,">$tmp_seq") || die "could not open $tmp_seq";
    $seq =~ s/[\s\012\015]+/ /g;
    print PAT "$seq\n";
    close(PAT);

    # check for protein or dna scan
    if ($params->{program} eq "Protein scan_for_matches") {
      @out = `$ext_bin/scan_for_matches -p $tmp_seq < $orgdir/$org/Features/peg/fasta`;
      $col_hdrs = ["peg","begin","end","string","function of peg"];
    } else {
      @out = `cat $orgdir/$org/contigs | $ext_bin/scan_for_matches -c $tmp_seq`;
      $col_hdrs = ["contig","begin","end","string"];
    }

    if (@out < 1) {
      push(@$html,$cgi->h1("Sorry, no hits"));
    } else {
      if (@out > 2000) {
	push(@$html,$cgi->h1("truncating to the first 1000 hits"));
	$#out = 1999;
      }
      for ($i=0; ($i < @out); $i += 2) {
	if ($out[$i] =~ /^>([^:]+):\[(\d+),(\d+)\]/) {
	 
	  $a = $1;
	  $b = $2;
	  $c = $3;
	  $d = $out[$i+1];
	  chomp $d;
	  if ($params->{program} eq "Protein scan_for_matches") {
	    push(@$tab, [ &HTML::fid_link($cgi,$a,1), $b, $c, $d, scalar $fig->function_of($a, $params->{user}) ]);
	  } else {
	    push(@$tab,[$a,$b,$c,$d]);
	  }
	}
      }
      push(@$html,&HTML::make_table($col_hdrs,$tab,"Matches"));
    }
  }

  # delete temporary file
  unlink($tmp_seq);

  # initialize content variable
  my $content = "<div class='blast'><pre>";

  # write result to content variable
  foreach (@$html) {
    $content .= $_;
  }
  
  # close content div
  $content .= "</pre></div>";

  # return html content string
  return $content;
}

sub execute_blastall {
    my($params) = @_;

    # get options from params hash
    my $prog    = $params->{program};
    my $input   = $params->{sequence_file};
    my $db      = $params->{database};
    my $options = $params->{options};
    my $ext_bin = $params->{fig_extbin};

    # initialize command line string
    my $blastall = $ext_bin . "blastall";
    my @args = ( '-p', $prog, '-i', $input, '-d', $db, split(/\s+/, $options) );

    print STDERR "command-line: '" . join(" ", $blastall, @args) . "'\n";

    # create filehandle
    my $bfh;
    my $pid = open( $bfh, "-|" );
    if ($pid == 0) {
      
      # execute blast
      exec( $blastall,  @args );
      die join(" ", $blastall, @args, "failed: $!");
    }

    # return blast output
    <$bfh>
}

sub call_tool {
  my($fig_or_sprout,$peg_id) = @_;

  # initialize some variables
  my($url,$method,@args,$line,$name,$val);
  
  # get the cgi object
  my $cgi = new CGI();
  
  # initialize html variable
  my $html = "";
  
  my $seq = &SeedComponents::Protein::get_translation($fig_or_sprout,$peg_id);
  if (! $seq) {
    $html = $cgi->h1("Sorry, $peg_id does not have a translation");
    return $html;
  }
  my $protQ = quotemeta $peg_id;
  
  my $tool = $cgi->param('tool');
  $/ = "\n//\n";
  my @tools = grep { $_ =~ /^$tool\n/ } `cat $FIG_Config::global/LinksToTools`;
  if (@tools == 1) {
    chomp $tools[0];
    (undef,undef,$url,$method,@args) = split(/\n/,$tools[0]);
    my $args = [];
    foreach $line (@args) {
	next if ($line =~ /^\#/); # ignore comments
	($name,$val) = split(/\t/,$line);
	$val =~ s/FIGID/$peg_id/;
	$val =~ s/FIGSEQ/$seq/;
	$val =~ s/\\n/\n/g;
	push(@$args,[$name,$val]);
      }
    
    my @result;
    
    if ($method =~/internal/i) {
      my $pegid;
      #If method is internal, then the url is actually a  perl script
      my $script = $url;
      $script=~ s/\.pl//g;
      
      my @script_array = &SeedComponents::Protein::flat_array(@$args);
      my $out = &FIG::run_gathering_output("$FIG_Config::bin/$script", @script_array);
      @result = split(/[\012\015]+/,$out);
      
    } else {
      @result = &HTML::get_html($url,$method,$args);
    }
    # From Bruce: Both Firefox and IE appear to be smarter than we are when it comes to coping
    # with the multiple heads and bodies, so I've commented out all this fixup stuff. If we need
    # to work on PDAs and cell phones at some future point, we can revisit this code.
    
    # some pages are setting the base
    #@result = grep {$_ !~ /base href/} @result;
    
    # and some pages have the audacity to add <head> and <body tags>
    # first remove them by regexp:
    #map {$_ =~ s/^.*<\/head>//i; $_ =~ s/^.*<body>//i} @result;
    #map {$_ =~ s/<\/body>.*$//i; $_ =~ s/<\/html>.*$//i} @result;
    #
    ## now try looping through
    #my $splice=0; my $splast=0;
    #foreach my $i (0..$#result) {
    #  if ($result[$i] =~ /<body>/i || $result[$i] =~ /<\/head>/i) {$splice=$i}
    #  if ($result[$i] =~ /<\/body>/i) {$splast=$i}
    #}
    #if ($splast) {
    #  splice(@result, -$splast);
    #}
    #if ($splice) {
    #  splice(@result, 0, $splice);
    #}
    
    foreach (@result) {
      $html .= $_;
    }
  }
  
  return $html;
}
