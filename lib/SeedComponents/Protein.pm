package SeedComponents::Protein;

use WebApplicationComponents qw(tabulator menu list table);

use AliTrees;
use AliTree;

use InterfaceRoutines;
use FIG;
use FIG_CGI;
use FIGRules;

my $sproutAvail = eval {
    require SproutFIG;
    require PageBuilder;
};

=head1 Protein Page Methods

The protein page consists of a set of blocks, each independant of one another. Each method in this module represents one of these blocks. All methods expect a reference to a parameter hash and will return a string of html. Typically the parameter hash consists of a fig-object reference and a PEG id. Some additional parameters might be necessary. Please refer to the detailed description of each method.

The Protein modules requires the WebApplicationComponents, InterfaceRoutines and FIG modules.

Example Usage:

    my $params = { fig_object  => $fig,
                   peg_id      => $peg,
                   table_style => 'enhanced' }

    my $attributes_table = SeedComponents::Protein::get_attributes($params);

=cut

use FIGjs;
use FIG_Config;
use FIGgjo;
use SimsTable;

use URI::Escape;
use HTML;
use Data::Dumper;

use strict;
use GenoGraphics;
use CGI;
use Tracer;
use BasicLocation;

###
#
# Content Generation Methods
#
###

# Table Blocks

=pod

=item * B<get_attributes> (fig_object, peg_id, table_style, initial_value)

Returns a table containing the attributes and their values of the PEG passed.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed, default is collapsed

=back

=cut

sub get_attributes {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style} || 'enhanced';
  my $id            = $parameters->{id}          || "attributes_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title}       || "Attributes";
  $parameters->{title} = $title;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('attributes_initial_value') || $parameters->{initial_value} || 'collapsed';
  $parameters->{initial_value} = $initial_value;

  # initialize variables
  my $body = "";
  my $table = "";
  my $links = "";

  # retrive list of attributes and sort it (case independent)
  my @attr = sort { (lc $a->[1] cmp lc $b->[1]) or (lc $a->[2] cmp lc $b->[2]) }
             $fig_or_sprout->get_attributes( $peg );

  # create column headers
  my $col_hdrs = ["Key<br><span style='font-size: smaller'>Link Explains Key</span>","Value"];

  # initialize rows variable
  my $rows = [];

  # iterate through attributes list
  foreach $_ (sort {$a->[0] cmp $b->[0]} @attr) {
    my($peg,$tag,$val,$url) = @$_;
    push(@$rows,[$tag, ($url =~ /^http:/ ? "<a href=\"$url\" target=_blank>$val</a>" : $val)]);
    if ($cgi->param("showtag") && $cgi->param("showtag") eq $tag) {
      my $data = &key_info($fig_or_sprout, $tag);
      my $info = "No Information Known about $tag";
      if ($data->{"description"}) {$info=$data->{"description"}}
      push(@$rows, [["Key", "th"], ["Explanation", "th"]], [$tag, $info]);
    }
  }

  my $headline = SeedComponents::Framework::get_headline($title);

  # generate help link
  $links .= "<a href='Html/Attributes.html' class='help' target='help'>Help on Attributes</a><br/>\n";
  $body .= $links . "<br/>";

  # determine if the returned table is to be plain or in enriched format
  if ($table_style eq 'enhanced') {
    my $table_params = { data       => $rows,
			 columns    => $col_hdrs,
			 perpage    => -1,
			 image_base => "Html/",
			 id         => "attributes"
		       };

    $table = &table($table_params);
  } else {
    $table = &HTML::make_table($col_hdrs,$rows);
  }
  $body .= $table;
  $parameters->{body} = $body;

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   links      => $links,
	   body       => SeedComponents::Framework::get_body($parameters),
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => $rows }
	 };
}

=pod

=item * B<get_protein_families> (fig_object, peg_id, table_style, initial_value)

Returns a table containing all protein families, their function and size of the PEG passed.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_protein_families {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id} || "protein_families_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Protein Families";
  $parameters->{title} = $title;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('protein_families_initial_value') || $parameters->{initial_value} || 'collapsed';
  $parameters->{initial_value} = $initial_value;

  # get username from cgi object
  my $username = $cgi->param('user');

  # initialize variables
  my $body = "";
  my $table = "";
  my $links = "";

  # initialize rows and column headers variables
  my $rows = [];
  my $col_hdrs;

  # get the families and other information
  my @families = &families_for_protein($fig_or_sprout,$peg);

  # if there are no families, return that none were found
  unless (scalar @families) {
    $body .= "<span class='message'>No protein families found</span>";
  } else {

    # set base url
    my $baseurl=$FIG_Config::cgi_base;

    # generate table rows
    foreach my $fam (@families) {
      my $link="<a href='proteinfamilies.cgi?user=$username&family=$fam'>$fam</a>";
      push @$rows, [$link || "&nbsp;", &family_function($fig_or_sprout, $fam) || "&nbsp;", &sz_family($fig_or_sprout, $fam) || "&nbsp;"];
    }

    # generate help link
    $links .= "<a href='Html/ProteinFamilies.html' class='help' target='help'>Help on Protein Families</a><br/><br/>";
    $body .= $links;

    $col_hdrs = ["Family ID<br><small>Link Investigates Family</small>", "Family Function", "Family Size"];

    # determine if the returned table is to be plain or in enriched format
    unless (defined($table_style)) {
      $table_style = 'enhanced';
    }
    if ($table_style eq 'enhanced') {
      my $table_params = { data       => $rows,
			   columns    => $col_hdrs,
			   perpage    => -1,
			   image_base => "Html/",
			   id         => "proteinfamilies"
			 };

      $table .= &table($table_params);
    } else {
      $table .= &HTML::make_table($col_hdrs,$rows);
    }
    $body .= $table;
  }

  $parameters->{body} = $body;
  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   links      => $links,
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => $rows }
	 };
}

=pod

=item * B<get_functional_coupling> (fig_object, peg_id, table_style, initial_value)

Returns a table with the functional coupling data

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_functional_coupling {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id} || "functional_coupling_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Functional Coupling";
  $parameters->{title} = $title;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('functional_coupling_initial_value') || $parameters->{initial_value} || 'collapsed';

  # get username from  cgi object
  my $user = $cgi->param('user');

  # initialize variables
  my $body = "";
  my $table = "";
  my $col_hdrs;

  # initialize some variables
  my($sc,$neigh);

  # set default parameters for coupling and evidence
  my ($bound,$sim_cutoff,$coupling_cutoff) = (5000, 1.0e-10, 4);

  # check if custom parameters are passed
  if ($cgi->param('fcbound')) { $bound           = $cgi->param('fcbound'); }
  if ($cgi->param('fcsim'))   { $sim_cutoff      = $cgi->param('fcsim');   }
  if ($cgi->param('fccoup'))  { $coupling_cutoff = $cgi->param('fccoup');  }

  # get the fc data
  my @fc_data = &coupling_and_evidence($fig_or_sprout,$peg,$bound,$sim_cutoff,$coupling_cutoff,1);

  # retrieve data
  my @rows = map { ($sc,$neigh) = @$_;
		[&get_evidence_link($neigh,$sc),$neigh,scalar &function_ofS($fig_or_sprout,$neigh,$user)]
	      } @fc_data;

  # set column headers
  $col_hdrs = ["Score","Peg","Function"];

  # determine if the returned table is to be plain or in enriched format
  unless (defined($table_style)) {
    $table_style = 'enhanced';
  }
  if ($table_style eq 'enhanced') {
    my $table_params = { data       => \@rows,
			 columns    => $col_hdrs,
			 perpage    => -1,
			 image_base => "Html/",
			 id         => "attributes"
		       };

    $table .= &table($table_params);
  } else {
    $table .= &HTML::make_table($col_hdrs,\@rows);
  }
  $body .= $table;
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => \@rows }
	 };
}

=pod

=item * B<get_chromosome_context> (fig_object, peg_id, table_style, min, max, features)

Returns a table with information about the chromosomal context.
If this is the only block called, there is no need to pass min, max and features.
If you already know min, max and features, pass them to prohibit redundency.
You can get these values by calling the get_region_data function.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<min>: The number of the smallest base

=item * I<max>: The number of the largest base

=item * I<feature_data>: feature data for all features in this region

=back

=cut

sub get_chromosome_context {
  my ($parameters) = @_;
  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $min           = $parameters->{min};
  my $max           = $parameters->{max};
  my $feat          = $parameters->{features};
  my $feature_data  = $parameters->{feature_data};
  my $id            = $parameters->{id} || "chromosome_context_block";
  $parameters->{id} = $id;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();
  my $is_sprout = FIGRules::nmpdr_mode($cgi);

  # check if the table style is set, otherwise set to default
  unless (defined($table_style)) {
    $table_style = 'enhanced';
  }

  # initialize variables
  my $body = "";
  my $table = "";

  # initialize variables, clean this up
  my($contig1,$beg1,$end1,$strand,$max_so_far,$gap,$comment,$fc,$aliases);
  my($fid1,$sz,$color,$map,$gg,$n,$link,$in_neighborhood,$fc_sc);

    my ($pegLocation) = $fig_or_sprout->feature_location($peg);
    Trace("Feature location for $peg is \"$pegLocation\".") if T(3);
    $contig1 = $fig_or_sprout->contig_of($pegLocation);

  # determine min, max and list of features for this peg if they were not passed
  unless (defined($feature_data)) {
    Trace("Retrieving region data.") if T(3);
    if (! defined ($min) || ! defined ($max)) {
        ($min, $max, $feat) = &get_region_data($parameters);
    }
    my $genomeID = FIG::genome_of($peg);

    # Each tuple consists of four (sic) elements:
    #   (1) the feature ID,
    #   (2) the feature location (as a comma-delimited list of location specifiers),
    #   (3) the feature aliases (as a comma-delimited list of named aliases),
    #   (4) the feature type,
    #   (5) the leftmost index of the feature's first location,
    #   (6) the rightmost index of the feature's last location,
    #   (7) the current functional assignment,
    #   (8) the user who made the assignment, and
    #   (9) the quality of the assignment (which is usually an empty string).
    $feature_data = $fig_or_sprout->all_features_detailed_fast($genomeID, $min, $max, $contig1);
    @$feature_data = sort { $a->[4]+$a->[5] <=> $b->[4]+$b->[5] } @$feature_data;

    my %featureHash = map { $_ => 1 } @$feat;
    $feature_data = [grep { $featureHash{$_->[0]} } @$feature_data];
    Trace("Region data ready.") if T(3);
  }

  # get user name and sprout option from the cgi object
  my $user = $cgi->param('user');

  # what does this do?
  Trace("Finding pins.") if T(3);
  my $in_cluster = &in_cluster_with($parameters);
  Trace("Setting column headers.") if T(3);
  # set column headers
  my $col_hdrs = ["Fid","Start","End","Size<br>(nt)","&nbsp;","Gap","Find<br>best<br>clusters","Pins","Fc-sc","SS",&get_evidence_codes_link(),"Function","Aliases"];

  # initialize table and gene variables
  my $rows  = [];
  my $genes = [];

  # initialize coupling hash
  my %coupled;
  Trace("Building subsystem links.") if T(3);
  # Make a pass over the features, determining what subsystems they appear in. Assign
  # unique ids for them.
  my %fid_to_subs;
  if ($is_sprout) {
    my @subs = $fig_or_sprout->{sprout}->GetAll(['IsLocatedIn', 'HasRoleInSubsystem'],
                                                'IsLocatedIn(to-link) = ? AND IsLocatedIn(beg) > ? AND IsLocatedIn(beg) + IsLocatedIn(len) < ?',
                                                [$contig1, $min, $max], ['HasRoleInSubsystem(from-link)', 'HasRoleInSubsystem(to-link)']);
    for my $sub (@subs) {
        if (exists($fid_to_subs{$sub->[0]})) {
            push @{$fid_to_subs{$sub->[0]}}, $sub->[1];
        } else {
            $fid_to_subs{$sub->[0]} = [$sub->[1]];
        }
    }
  }
  for my $feature_datum (@$feature_data) {
    if (! exists $fid_to_subs{$feature_datum->[0]}) {
        $fid_to_subs{$feature_datum->[0]} = [$fig_or_sprout->peg_to_subsystems($feature_datum->[0])];
    }
  }
  my %subs;
  for my $feature_datum (@$feature_data) {
    # $feature_datum consists of nine elements: (0) the feature ID, (1) the feature location (as a comma-delimited list of location specifiers),
    # (2) the feature aliases (as a comma-delimited list of named aliases), (3) the feature type, (4) the leftmost index of the feature's leftmost
    # location, (5) the rightmost index of the feature's rightmost location, (6) the current functional assignment, (7) the user who made the
    # assignment, and (8) the quality of the assignment (which is usually a space).
    my $fid = $feature_datum->[0];
    my $subs = $fid_to_subs{$fid};
    map { $subs{$_}++ } @$subs;
  }

  my $sub_idx = 1;
  my %sub_names;
  for my $sub (sort { $subs{$b} <=> $subs{$a} } keys %subs) {
    $sub_names{$sub} = $sub_idx++;
  }

  my $sprout = $is_sprout ? '&SPROUT=1' : '';

  # iterate through all features of the context, generating one row in the table each time
  for my $feature_datum (@$feature_data) {
    # $feature_datum consists of nine elements: (0) the feature ID, (1) the feature location (as a comma-delimited list of location specifiers),
    # (2) the feature aliases (as a comma-delimited list of named aliases), (3) the feature type, (4) the leftmost index of the feature's leftmost
    # location, (5) the rightmost index of the feature's rightmost location, (6) the current functional assignment, (7) the user who made the
    # assignment, and (8) the quality of the assignment (which is usually a space).
    my $fid1 = $feature_datum->[0];
    Trace("Computing boundaries.") if T(4);
    # generate the cell information for beg and end
#    ($beg1, $end1) = ($feature_datum->[4], $feature_datum->[5]);
    (undef,$beg1,$end1) = $fig_or_sprout->boundaries_of($feature_datum->[1]);
    # generate the cell information for size
    $sz = abs($end1-$beg1)+1;

    # generate the cell information for strand
    $strand = ($beg1 < $end1) ? "+" : "-";

    # generate the cell information for find best clusters
    my $best_clusters_link = "<a href=$FIG_Config::cgi_url/homologs_in_clusters.cgi?prot=$fid1&user=$user$sprout><img src=\"Html/button-cl.png\" border=\"0\"></a>";

    # generate the cell information for fc-sc and pins
    if (defined($fc_sc = $in_cluster->{$fid1})) {
      $fc = &pin_link($cgi,$fid1);
    } else {
      $fc    = "";
      $fc_sc = "";
    }
    Trace("Processing translations.") if T(4);
    # generate the cell information for function
    $parameters->{peg_id_curr} = $fid1;
    $comment = &get_translation_function($parameters);
    Trace("Processing EC links.") if T(4);
    $comment = &set_ec_and_tc_links($fig_or_sprout,&genome_of($fid1),$comment);
    Trace("Fixing colors.") if T(4);
    # highlight the function cell of the selected peg
    if ($fid1 eq $peg) {
      if ($table_style eq 'enhanced') {
	$comment = "|^background-color: #00FF00;^|$comment";
      } else {
	$comment = "\@bgcolor=\"#00FF00\":$comment";
      }
    }

    # generate the cell information for in subsystem (SS)
    my @in_sub = @{$fid_to_subs{$fid1}};
    my $in_sub;
    if (@in_sub > 0) {
      if ($is_sprout) {
	$in_sub = @in_sub;
      } else {
	$in_sub = @in_sub;
	$in_sub .= ": " . join(" ", map { $sub_names{$_} } sort {$b cmp $a} @in_sub);

	my $ss_list=join "<br>", map { my $g = "$sub_names{$_} : $_"; $g =~ s/_/ /g; $_=$g } sort {$b cmp $a} @in_sub;
	$in_sub = $cgi->a(
			  {
			   id=>"subsystems", onMouseover=>"javascript:if(!this.tooltip) this.tooltip=new Popup_Tooltip(this, 'Subsystems', '$ss_list', ''); this.tooltip.addHandler(); return false;"}, $in_sub),
			 }
    } else {
      $in_sub = "&nbsp;";
    }
    Trace("Retrieving evidence codes.") if T(4);
    # generate the cell information for evidence codes
    my $ev_codes=" &nbsp; ";
    my @ev_codes=&evidence_codes($fig_or_sprout,$fid1);
    if (scalar(@ev_codes) && $ev_codes[0]) {
      my $ev_code_help=join("<br />", map {&HTML::evidence_codes_explain($_)} @ev_codes);
      $ev_codes = $cgi->a(
			  {
			   id=>"evidence_codes", onMouseover=>"javascript:if(!this.tooltip) this.tooltip=new Popup_Tooltip(this, 'Evidence Codes', '$ev_code_help', ''); this.tooltip.addHandler(); return false;"}, join("<br />", @ev_codes));
      $ev_codes =~ s/dlit\((\d+)\)/dlit\(<a href='http:\/\/www\.ncbi\.nlm\.nih\.gov\/entrez\/query\.fcgi\?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids=$1' target='_blank'>$1<\/a>\)/g;
      $ev_codes =~ s/ilit\((\d+)\)/ilit\(<a href='http:\/\/www\.ncbi\.nlm\.nih\.gov\/entrez\/query\.fcgi\?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids=$1' target='_blank'>$1<\/a>\)/g;
    }
    Trace("Retrieving aliases.") if T(4);
    # generate the cell information for alias
    my $aliases = $feature_datum->[2];
    $aliases =~ s/,(\S)/, $1/g; # Insure there are spaces so that the cell wraps.
    $aliases = &HTML::set_prot_links($cgi,$aliases), $aliases =~ s/SPROUT=1/SPROUT=0/g;
    $aliases =~ s/[&;]user=[^&;]+[;&]/;/g;
    $aliases = $aliases ? $aliases : "&nbsp;";

    # generate the cell information for gap
    if ($max_so_far) {
      $gap = (&min($beg1,$end1) - $max_so_far) - 1;
    } else {
      $gap = "&nbsp;";
    }
    $max_so_far = &max($beg1,$end1);
    Trace("Generating table row.") if T(4);
    # generate table row
    push(@$rows, [&HTML::fid_link($cgi,$fid1,"local"),
		  $beg1,
		  $end1,
		  $sz,
		  $strand,
		  $gap,
		  $best_clusters_link,
		  $fc ? $fc : "&nbsp;",
		  $fc_sc ? $fc_sc : "&nbsp;",
		  $in_sub,
		  $ev_codes,
		  $comment || "&nbsp;",
		  $aliases]);

  }

  # determine if the returned table is to be plain or in enriched format
  if ($table_style eq 'enhanced') {
    my $table_params = { data       => $rows,
			 columns    => $col_hdrs,
			 perpage    => -1,
			 image_base => "Html/",
			 id         => "neighborhood"
		       };

    $table .= &table($table_params);
  } else {
    $table .= &HTML::make_table($col_hdrs,$rows);
  }
  $body .= $table;
  $parameters->{body} = $body;

  # create title
  my $title = $parameters->{title} || "Context on contig $contig1 from base $min to $max (".(abs($max-$min)+1)." bp)";
  $parameters->{title} = $title;

  my $headline = SeedComponents::Framework::get_headline($title);
  Trace("Returning from context method.") if T(3);
  # return data hash
  return { id => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => $rows }
	 };
}

=pod

=item * B<get_subsys_connections> (fig_object, peg_id, table_style, initial_value)

Returns a table of the subsystem the current peg is in.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_subsystem_connections {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id} || "subsystems_connections_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Subsystems in Which This Protein Plays a Role";
  $parameters->{title} = $title;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('subsystem_connections_initial_value') || $parameters->{initial_value} || 'collapsed';

  # get username from cgi object
  my $user = $cgi->param('user') || "";

  # initialize html variable
  my $body = "";
  my $table = "";

  # initialize column headers and rows variables
  my $col_hdrs;
  my $rows;

  # check if the selected peg is part of a subsystem
  if (my @subsystems = $fig_or_sprout->subsystems_for_peg($peg)) {

    # set column headers
    $col_hdrs = ["Subsystem", "Curator", "Role"];

    # test for sprout
    my $sprout = $cgi->param('SPROUT') ? 1 : "";
    my $virt = $cgi->param("48hr_job");

    # iterate through the list of subsystems this peg is in
    for my $ent (@subsystems) {
      my($sub, $role) = @$ent;

      # determine curator of this subsystem
      my $curator = &subsystem_curator($fig_or_sprout,$sub);
      my $can_alter;
      my $esc_sub = uri_escape($sub);
      my $genome = &FIG::genome_of($peg);

      # generate an options hash for the link parameters
      my %opts = ( $sprout ? ( SPROUT => $sprout ) : (),
                   user => $user,
                   ssa_name => $esc_sub,
                   focus => $genome,
                   request => 'show_ssa',
                   show_clusters => 1,
                   sort => 'by_phylo',
                   $virt ? ( '48hr_job' => $virt ) : (),
                 );

      # check if the user is the curator of this subsystem
      if ($user eq $curator) { $opts{can_alter} = 1 }

      # generate the link
      my $opts = join("&", map { "$_=$opts{$_}" } keys(%opts));
      my $url = $cgi->a({href => "display_subsys.cgi?$opts"}, $sub);

      # push the row into the rows array
         # add an "*" as a prefix for auxiliary roles if you are in the SEED environment
      my $aux = ((! $sprout) && (! $virt) && ($fig_or_sprout->is_aux_role_in_subsystem($sub,$role))) ?
	        "*" : "";
      push(@$rows, [$url, $curator, $aux . $role]);
    }

    # determine if the returned table is to be plain or in enriched format
    unless (defined($table_style)) {
      $table_style = 'enhanced';
    }
    if ($table_style eq 'enhanced') {
      my $table_params = { columns => $col_hdrs,
			   data    => $rows,
			   perpage    => -1,
			   id         => "subsystems_connections_table",
			   image_base => "./Html/" };
      $table .= table($table_params);
    } else {
      $table .= &HTML::make_table($col_hdrs,$rows);
    }
    $body .= $table;
  } else {

    # the peg is not present in any subsystem, return the according message
    $body .= "<span class='message'>This PEG is currently not present in any subsytem.</span>";
  }
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => $rows }
	 };

}

=pod

=item * B<get_aa_sequence> (fig_object, peg_id, collapsable, noheadline, initial_value)

Returns the aminoacid sequence of the PEG

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_aa_sequence {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $id            = $parameters->{id} || "aa_sequence_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Protein Sequence";
  $parameters->{title} = $title;

  # initialize some variables
  my($seq,$func,$i);

  # get cgi object and usernam
  my $cgi = $parameters->{cgi} || new CGI();
  my $user = $cgi->param('user');
  my $initial_value = $cgi->param('aa_sequence_initial_value') || $parameters->{initial_value} || 'collapsed';

  # initialize variables
  my $body = "";
  my $data = "";

  # get the sequence
  if ($seq = &get_translation($fig_or_sprout,$peg)) {
    $func  = &function_ofS($fig_or_sprout,$peg,$user);
    my $md5 = FIG::md5_of_peg( $fig_or_sprout, $peg );
    $data  = ">$peg $func\n" . $seq;
    $body .= join( "\n", $cgi->pre . ">$peg $func",
                         ( $seq =~ m/(.{1,60})/g ),
                         ( $md5 ? "\nMD5 = $md5" : () ),
                         $cgi->end_pre,
                         ''
                 );
  } else {
    $body .= "<span class='message'>No translation available for $peg</span>";
  }
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   data       => $data
	 };
}

=pod

=item * B<get_dna_sequence> (fig_object, peg_id, initial_value)

Returns the dna sequence of the PEG

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_dna_sequence {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $id            = $parameters->{id} || "dna_sequence_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "DNA Sequence";
  $parameters->{title} = $title;

  # initialize some variables
  my($seq,$func,$i);

  # get cgi object and usernam
  my $cgi = $parameters->{cgi} || new CGI();
  my $user = $cgi->param('user');
  my $initial_value = $cgi->param('dna_sequence_initial_value') || $parameters->{initial_value} || 'collapsed';

  # initialize variables
  my $body = "";
  my $data = "";

  # get the sequence
  if ($seq = &dna_seq($fig_or_sprout,&genome_of($peg),&feature_locationS($fig_or_sprout,$peg))) {
    $func = &function_ofS($fig_or_sprout,$peg,$user);
    $data = ">$peg $func\n" . $seq;
    $body .= $cgi->pre . ">$peg $func\n";
    for ($i=0; ($i < length($seq)); $i += 60) {
      if ($i > (length($seq) - 60)) {
	$body .= substr($seq,$i) . "\n";
      } else {
	$body .= substr($seq,$i,60) . "\n";
      }
    }
    $body .= $cgi->end_pre;
  } else {
    $body .= "<span class='message'>No DNA sequence available for $peg</span>";
  }
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   data       => $data
	 };
}

=pod

=item * B<get_dna_sequence_adjacent> (fig_object, peg_id, initial_value)

Returns the dna sequence of the PEG, including the 500 bp upstream and downstream

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_dna_sequence_adjacent {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $id            = $parameters->{id} || "dna_sequence_adjacent_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "DNA with Flanking Sequence";
  $parameters->{title} = $title;

  # initialize some variables
  my($func,$i);

  # get cgi object and usernam
  my $cgi = $parameters->{cgi} || new CGI();
  my $user = $cgi->param('user');
  my $initial_value = $cgi->param('dna_sequence_adjacent_initial_value') || $parameters->{initial_value} || 'collapsed';

  # initialize variables
  my $body = "";
  my $data;

  my $additional = $cgi->param("additional_sequence");
  defined( $additional ) or ( $additional = 500 );

  # Now handles segmented location and running off an end. -- GJO
  my $genome = &genome_of( $peg );
  my $loc = &feature_locationS($fig_or_sprout,$peg);
  my @loc = split /,/, $loc;

  my ($contig, $beg, $end) = BasicLocation::Parse($loc[0]);
  my $seq = "";
  if(defined($contig) and defined($beg) and defined($end)) {

    my ( $n1, $npre );
    if ( $beg < $end )
      {
	$n1 = $beg - $additional;
	$n1 = 1 if $n1 < 1;
	$npre = $beg - $n1;
      }
    else
      {
	$n1 = $beg + $additional;
	my $clen = $fig_or_sprout->contig_ln( $genome, $contig );
	$n1 = $clen if $n1 > $clen;
	$npre = $n1 - $beg;
      }
    $loc[0] = join( '_', $contig, $n1, $end );

    # Add to the end of the last segment:

    ( $contig, $beg, $end ) = BasicLocation::Parse($loc[-1]);

    my ( $n2, $npost );
    if ( $beg < $end )
      {
	$n2 = $end + $additional;
	my $clen = $fig_or_sprout->contig_ln( $genome, $contig );
	$n2 = $clen if $n2 > $clen;
	$npost = $n2 - $end;
      }
    else
      {
	$n2 = $end - $additional;
	$n2 = 1 if $n2 < 1;
	$npost = $end - $n2;
      }
    $loc[-1] = join( '_', $contig, $beg, $n2 );

    $seq = $fig_or_sprout->dna_seq( $genome, join( ',', @loc ) );
    if ( ! $seq ) {
      $body .= "<span class='message'>No DNA sequence available for $peg</span>";
      return { id         => $id,
	       button     => SeedComponents::Framework::get_button($parameters),
	       title      => SeedComponents::Framework::get_headline($title),
	       body       => $body,
	       data       => "" };
    }

    my $len = length( $seq );         # Get length before adding newlines
    $seq =~ s/(.{60})/$1\n/g;         # Cleaver way to wrap the sequence
    my $p1 = $npre + int( $npre/60 ); # End of prefix, adjusted for newlines
    my $p2 = $len - $npost;           # End of data,
    $p2 += int( $p2/60 );             #     adjusted for newlines
    my $diff = $p2 - $p1;             # Characters of data

    # Integrate the HTML codes
    $seq = substr($seq, 0, $p1) . '<SPAN Style="color:red">' . substr($seq, $p1, $diff) . '</SPAN>' . substr($seq, $p2);

    # regexp can't handle more than 32766 bytes
    #$seq =~ s/^(.{$p1})(.{$diff})(.*)$/$1<SPAN Style="color:red">$2<\/SPAN>$3/s;
    $data = [">$peg $func\n", $1, $2, $3];
    $func = $fig_or_sprout->function_of( $peg, $user );

    $body .= $cgi->pre .  ">$peg $func\n$seq\n" .  $cgi->end_pre;

  } else {
    $body .= "<span class='message'>No DNA sequence available for $peg</span>";
  }
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   data       => $data
	 };
}

# Other Blocks

=pod

=item * B<get_links> (fig_object, peg_id, table_style, initial_value)

Returns a table of the subsystem the current peg is in.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_links {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id} || "links_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Links to Related Entries in Other Sites";
  $parameters->{title} = $title;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('links_initial_value') || $parameters->{initial_value} || 'collapsed';
  $parameters->{initial_value} = $initial_value;

  # initialize html variable
  my $body = "";
  my $table = "";
  my $links = "";

  # initialize rows and columns variable
  my $rows = [];
  my $col_hdrs = [];

  # retrive the link for this peg
  my @links = &peg_links($fig_or_sprout, $peg);

  # check if any links exists
  if (@links > 0) {

    # create column headers
    $col_hdrs = [1,2,3,4,5];

    # make each row 5 columns long
    my ($n,$i);
    for ($i=0; ($i < @links); $i += 5) {
      $n = (($i + (5-1)) < @links) ? $i+(5-1) : $i+(@links - $i);
      push(@$rows,[@links[$i..$n]]);
    }

    # determine if the returned table is to be plain or in enriched format
    unless (defined($table_style)) {
      $table_style = 'enhanced';
    }
    if ($table_style eq 'enhanced') {
      my $table_params = { columns    => $col_hdrs,
			   data       => $rows,
			   perpage    => -1,
			   id         => "links_table",
			   image_base => "./Html/" };
      $table .= table($table_params);

    } else {
      $table .= HTML::make_table($col_hdrs,$rows);
    }
    $body .= $table;
  } else {

    # no links exist for this peg
    $body .= "<span class='message'>This PEG has no links.</span>";
  }

  # if this is not sprout, include the ability to add links
  if (! $cgi->param('SPROUT')) {
    my $url = "$FIG_Config::cgi_url/add_links.cgi?peg=$peg";
    $links .= "<a href='$url'>add a new link</a>";
    $body .= "<br/>" . $links;
  }
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   links      => $links,
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => $rows }
	 };
}

=pod

=item * B<get_show_assignments> (fig_object, peg_id, table_style, initial_value)

Returns a table of the assignments of essentially identical proteins.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_show_assignments {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id} || "show_assignments_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Assignments for Essentially Identical Proteins";
  $parameters->{title} = $title;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('show_assignments_initial_value') || $parameters->{initial_value} || 'collapsed';

  # initialize html variable
  my $body = "";
  my $table = "";

  # create column headers
  my $col_hdrs = ["Ontology","Organism","Assignment", "Link"];

  # retrieve data with get_identical_protein_data
  my $data = &get_identical_protein_data($parameters);
  my $rows = [ map { [ $_->{who}, $_->{organism}, $_->{assignment}, $_->{id} ] } @$data ];

  # check if the table contains any rows
  if (@$rows > 0) {

    # determine if the returned table is to be plain or in enriched format
    unless (defined($table_style)) {
      $table_style = 'enhanced';
    }
    if ($table_style eq 'enhanced') {

      my $table_params = { columns => $col_hdrs,
			   data    => $rows,
			   perpage    => -1,
			   id         => "assignments_table",
			   image_base => "./Html/" };
      $table .= table($table_params);

    } else {
      $table .= HTML::make_table($col_hdrs,$rows);
    }
    $body .= $table;
  }
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => $headline,
	   body       => SeedComponents::Framework::get_body($parameters),
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => $rows }
	 };
}

=pod

=item * B<get_assignments_for_identical_proteins> (fig_object, peg_id, table_style, initial_value)

Returns a table of the assignments of essentially identical proteins which allows for quick annotaion.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut

sub get_assignments_for_identical_proteins {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id} || "assignments_for_identical_proteins_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Assignments for Essentially Identical Proteins";
  $parameters->{title} = $title;

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('assignments_for_identical_proteins_initial_value') || $parameters->{initial_value} || 'collapsed';

  # check if table style is passed, otherwise set to default
  unless (defined($table_style)) {
    $table_style = 'enhanced';
  }

  # initialize html variable
  my $body  = "";
  my $table = "";

  # create column headers
  my $col_hdrs = ["Id","Organism","Who","ASSIGN","Assignment"];

  # retrieve data with get_identical_protein_data
  my $proteindata = &get_identical_protein_data($parameters);
  my $rows = [ map { [ $_->{id}, $_->{organism}, $_->{who}, $_->{assign}, $_->{assignment} ] } @$proteindata ];

  # check if the table contains any rows
  if (@$rows > 0) {

    # determine if the returned table is to be plain or in enriched format
    unless (defined($table_style)) {
      $table_style = 'enhanced';
    }
    if ($table_style eq 'enhanced') {

      my $table_params = { columns => $col_hdrs,
                           data    => $rows,
                           perpage    => -1,
                           id         => "assignments_table",
                           image_base => "./Html/" };
      $table .= table($table_params);

    } else {
      $table .= HTML::make_table($col_hdrs,$rows);
    }
    $body .= $table;
  } else {
    $body = "<span class='message'>No essentially identical proteins found</span>";
  }
  $parameters->{body} = $body;

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
           button     => SeedComponents::Framework::get_button($parameters),
           title      => $headline,
           body       => SeedComponents::Framework::get_body($parameters),
           table      => $table,
           table_data => { columns => $col_hdrs,
                           rows    => $rows }
         };
}

=pod

=item * B<get_similarities> (fig_object, peg_id, table_style, initial_value)

Returns a table displaying the similarities.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=item * I<initial_value>: can be either 'collapsed' or 'expanded', meaning if the information is initially hidden or displayed

=back

=cut
#*****************************************************************************

# <<'End_of_new_version';
sub get_similarities {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id}    ||= "similarities_block";
  my $title         = $parameters->{title} ||= "Similarities";

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();
  my $sprout = $cgi->param('SPROUT') || 0;

  my $initial_value = $cgi->param('similarities_initial_value') || $parameters->{initial_value} || 'collapsed';

  # check if table style is passed, otherwise set to default
  $table_style = 'enhanced' unless (defined($table_style));

  # initialize html variable

  my @body  = ();

  # retrieve user name from cgi object
  my $user = $cgi->param('user') || "";

  # get the function of the peg in question
  my $current_func = &trans_function_of($fig_or_sprout, $cgi, $peg);

  my $link .= "<A href=\"Html/similarities_options.html\" target=\"help\" class=\"help\">Help with SEED similarities options</A>";
  push @body, $link . "<BR />";

  # insert the request form
  my $translatable = &translatable($fig_or_sprout,$peg);
  if ( (! $cgi->param('sims') ) && $translatable) {
    $parameters->{short_form} = 1;
  } else {
    $parameters->{short_form} = 0;
  }
  my $form = &get_sims_request_form($parameters);

  my($ali_trees,@alis,$ali,$phob,$sz,$from,$label);
  if ($user && ($ali_trees = new AliTrees($fig_or_sprout)))
  {
      Trace("Creating trees.") if T(1);
      my $have_tree = 0;
      foreach $ali ($ali_trees->alignments_containing_peg($peg))
      {
          next if (! -s "$FIG_Config::data/AlignmentsAndTrees/Library/$ali/tree.newick");
          my $ali_tree = new AliTree($ali,$fig_or_sprout);
          if ($ali_tree && ($phob = $ali_tree->phob_dir))
          {
              $sz = $ali_tree->sz;
              $from = "fig\|$ali";
              $from =~ s/-\d+$//;
              my $gs = $fig_or_sprout->genus_species(&FIG::genome_of($from));
              my $funcA = $fig_or_sprout->function_of($from);
              $label = "Annotate using tree of size $sz centered on $from [$gs: $funcA]";
              my $link_root = "assign_using_tree.cgi?user=$user&full_path=$phob";
              my $link = "<a href=\"$link_root\">$label</a>";
              my $xml_link = "<a href=\"tree_jnlp.cgi?user=$user&full_path=$phob\":>Use JAVA Tree Tool </a>";
              push @body, "$link<BR />\n";
              push @body, "$xml_link<BR /><BR />\n";
              # print STDERR "$link \n";
              $have_tree++;
          }
      }
      if ( $have_tree ) {
          push @body, "The JAVA tool will download and run a JAVA application. It may ask you if you want to open or save the file. Select Open<BR /><BR />\n";
      }
  } else {
        Trace("Not creating trees.") if T(1);
  }

  # check if the similarities have been requested, if so display them
  my $table;
  if ($cgi->param('sims')) {

    # get the parameters for the similarities calculation
    my $form_params = &get_similarity_parameters();

    my $maxN            = $form_params->{maxN};
    my $max_expand      = $form_params->{max_expand};
    my $maxP            = $form_params->{maxP};
    my $select          = $form_params->{select};
    my $show_env        = $form_params->{show_env};
    my $show_alias      = $form_params->{show_alias};
    my $sort_by         = $form_params->{sort_by};
    my $group_by_genome = $form_params->{group_by_genome};
    my $expand_groups   = $form_params->{expand_groups};

    # calculate the sims
    my @sims = sims( $fig_or_sprout,
                     $peg,
                     $maxN,
                     $maxP,
                     $select,
                     $max_expand,
                     $group_by_genome,
                     $form_params
		           );

    # check if any sims where returned
    if ( @sims ) {
        # {
        #     require Digest::MD5;
        #     my $addr = $ENV{ REMOTE_ADDR };
        #     my $host = $ENV{ REMOTE_HOST };
        #     my $rem_id = substr( Digest::MD5::md5_hex( $addr ), 0, 8 );
        #     print STDERR "$rem_id = $host\n";
        #     push @body, "<B>Hex = <FONT Color=#FF0000>$rem_id</FONT></B><BR />";
        # }

        my @cols = qw( checked s_id e_val/identity s_region q_region from s_subsys s_evidence s_def s_genome );
        push @cols, 's_aliases'  if $show_alias;
        $parameters->{ col_request } = \@cols;
        push @body, SimsTable::similarities_table( $fig_or_sprout, $cgi, \@sims, $peg, $parameters );
    }
  }

  $parameters->{body} = join( '', @body );

  my $headline = SeedComponents::Framework::get_headline($title);

  # return data hash
  return { id         => $id,
           button     => SeedComponents::Framework::get_button($parameters),
           title      => $headline,
           form       => $form,
           body       => SeedComponents::Framework::get_body($parameters),
           table      => $table,
         # table_data => { columns => $col_hdrs, rows => $rows }
	 };
}
# End_of_new_version


=pod

=item * B<get_pubmed_url> get_tools> (fig_object, peg_id)

Returns the pubmed url for the peg. Uses the gi ids

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=back

=cut

sub get_pubmed_url {
    my ($parameters) = @_;

    # retrieve parameters from parameter hash

    my $fig_or_sprout = $parameters->{fig_object};
    my $protein_peg   = $parameters->{peg_id};

    my @aliases = $fig_or_sprout->feature_aliases($protein_peg);
    my @gid = grep {/.*gi.*/} @aliases;
    my @spid = grep {/.*sp.*/} @aliases;
    my @unid = grep {/.*uni.*/} @aliases;
    my @geneid = grep {/.*GeneID.*/} @aliases;

    my @all_ids;
    push (@all_ids, @gid);
    push (@all_ids, @spid);
    push (@all_ids, @geneid);
    push (@all_ids, @unid);
    # if (@all_ids == 0) { return "" }
    my $all_ids_query = join (" ", @all_ids);
    my $pubmed_url;
    my $cgi = $parameters->{cgi} || new CGI();

    if ($cgi->param('SPROUT')) {
        $pubmed_url = "<input type=button value='Literature' onclick='window.open(\"nmpdr_aliases_to_pubmed.cgi?ids=$all_ids_query&peg=$protein_peg\")'>";
    } else {
        $pubmed_url = "<input type=button value='Get or Curate Literature' onclick='window.open(\"aliases_to_pubmed.cgi?ids=$all_ids_query&peg=$protein_peg\")'>";
    }

    return $pubmed_url;
}



=pod

=item * B<get_tools> (fig_object, peg_id, table_style)

Returns the links to run tools on this PEG

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<table_style>: 'plain' or 'enhanced'. Default is 'enhanced'

=back

=cut

sub get_tools {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $table_style   = $parameters->{table_style};
  my $id            = $parameters->{id} || "tools_block";
  $parameters->{id} = $id;
  my $title         = $parameters->{title} || "Tools to Analyze Protein Sequences";
  $parameters->{title} = $title;

  # get current cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  my $initial_value = $cgi->param('similarities_initial_value') || $parameters->{initial_value} || 'collapsed';

  # initialize variables
  my $body = "";
  my $table = "";
  my $rows = [];
  my $col_hdrs = [];

  # generate the link to turn tools on or off
  my $toollink = $cgi->url(-relative => 1, -query => 1, -path_info => 1);

  $toollink =~ s/[\&\;]fulltools.*[^\;\&]/\&/;
  my $fulltoolbutton  = $cgi->a({href=> $toollink . "&fulltools='1'"}, "> Show tool descriptions");
  my $brieftoolbutton = $cgi->a({href=> $toollink}, "< Hide tool descriptions");

  $cgi->param(-name => "request",
	      -value => "use_protein_tool");
  my $url = $cgi->url(-relative => 1, -query => 1, -path_info => 1);

  if (open(TMP,"<$FIG_Config::global/LinksToTools")) {
    $col_hdrs = ["Tool","Description"];

    $/ = "\n//\n";
    my $brieftools; # in case we don't want descriptions and whatnot
    while (defined($_ = <TMP>)) {
      # allow comment lines in the file
      next if (/^#/);
      my($tool,$desc, undef, $internal_or_not) = split(/\n/,$_);

      #KSH modified - only show general tools and tools that are specific to the organism
      my $tool_org = $peg;
      $tool_org=~ s/fig\|//;
      $tool_org=~ s/\.peg.*//;
      next if (($tool ne 'ProDom') && ($internal_or_not eq "INTERNAL") && ($desc != $tool_org));

      # RAE modified this so we can include column headers.
      undef($desc) if ($desc eq "//"); # it is a separator
      # RAE modified again so that we only get a short tool list instead of the big table if that is what we want.
      if ($cgi->param('fulltools')) {
	if ($desc) {
	  push(@$rows,["<a href=\"$url\&tool=$tool\">$tool</a>",$desc]);
	} else {
	  push(@$rows, [["<strong>$tool</strong>", "td colspan=2 align=center"]]);
	}
      } else {
	if ($desc) {
	  $brieftools .= " &nbsp; <a href=\"$url\&tool=$tool\">$tool</a> &nbsp;|";
	}
      }
    }
    close(TMP);
    $/ = "\n";
    if ($brieftools) {
      $body .= $cgi->p("|" . $brieftools) . $fulltoolbutton;
    } else {

      # determine if the returned table is to be plain or in enriched format
      unless (defined($table_style)) {
	$table_style = 'enhanced';
      }
      if ($table_style eq 'enhanced') {
	my $table_params = { data       => $rows,
			     columns    => $col_hdrs,
			     perpage    => -1,
			     image_base => "Html/",
			     id         => "attributes"
			   };

	$table .= &table($table_params);
      } else {
	$table .= &HTML::make_table($col_hdrs,$rows);
      }
      $body .= $table;
      $body .= "<br/>". $brieftoolbutton;
    }
  }
  $cgi->delete('request');

  $parameters->{body} = $body;

  # return data hash
  return { id         => $id,
	   button     => SeedComponents::Framework::get_button($parameters),
	   title      => SeedComponents::Framework::get_headline($title),
	   body       => SeedComponents::Framework::get_body($parameters),
	   table      => $table,
	   table_data => { columns => $col_hdrs,
			   rows    => $rows }
	 };
}

=pod

=item * B<get_annotation_links> (peg_id)

Returns the html with the list of links to annotate

=over 2

=item * I<peg_id>: the id of the PEG in question

=back

=cut

sub get_annotation_links {
  my ($parameters) = @_;

  # get parameters from parameters hash
  my $prot = $parameters->{peg_id};

  # get the current cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # retrieve user and sprout information from cgi object
  my $user = $cgi->param('user') || "";
  my $is_sprout = FIGRules::nmpdr_mode($cgi);

  # initialize html variable
  my $html = "";

  # use a table so that the help can be positioned at the far right:
  $html .= "<TABLE><TR>\n<TD>\n";

  my $virt   = $cgi->param("48hr_job") ? "&48hr_job=" . $cgi->param("48hr_job") : '';
  my $sprout = $is_sprout              ? '&SPROUT=1'                            : '';

  # determine the current url
  my $link = "$FIG_Config::cgi_url/fid_checked.cgi";
  if ($user) {
    # construct the links for annotation
    my $nlink   = $link . "?fid=$prot&user=$user&checked=$prot$virt$sprout&assign/annotate=assign/annotate";
    my $notlink = $link . "?fid=$prot&user=$user&checked=$prot$virt$sprout&assign/annotate=assign/annotate&negate=1";

    # add the links to annotate / negate annotation
    $html .= "<a href='$nlink' target='_blank'>Annotate</a>&nbsp;&nbsp;&nbsp; [<a href='$notlink' target='_blank'>Negate Annotation</a>]&nbsp;&nbsp; /&nbsp;&nbsp;\n";
  }
  my $base = $cgi->url(-relative => 1, -query => 1, -path_info => 1);
  my $link1 = "$base&request=view_annotations";
  my $link2 = "$base&request=view_all_annotations";

  $html .= "<a href=$link1>Annotation History</a> &nbsp;&nbsp;/ &nbsp;&nbsp;<a href=$link2>View All Related Annotations</a>\n";
  $html .= "</TD>";

  # check if this is sprout or seed for the help link
  if (not $is_sprout) {
    $html .= "<TD NoWrap Width=1%><a href='./Html/seedtips.html#gene_names' class='help' target='help'>Help on Annotations</a></TD>\n";
  }
  $html .= "</TR></TABLE>\n";

  return $html;
}

=pod

=item * B<get_evidence> (fig_object, peg_id)

Returns the html stating the evidence

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=back

=cut

sub get_evidence {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg          = $parameters->{peg_id};

  # initialize html string
  my $html = "<ul>";

  # retrieve the evidence codes for this PEG
  my @codes = &evidence_codes($fig_or_sprout, $peg);

  # parse the codes into readable strings
  foreach my $code (@codes) {
    if ($code =~ /^icw\((\d+)\)$/) {
      $html .= "<li><b>icw($1)</b><br/>This PEG occurs in a cluster with $1 other genes from the same subsystem<br/><br/>";
    } elsif ($code =~ /^isu$/) {
      $html .= "<li><b>isu</b><br/>This PEG occurs in a subsystem, and it is the only PEG for that genome that has been assigned the functional role<br/><br/>";
    } elsif ($code =~ /^idu\((\d+)\)$/) {
      $html .= "<li><b>idu($1)</b><br/> This PEG occurs in a subsystem, but it has $1 duplicates and is not clustered<br/><br/>";
    } elsif ($code =~ /^IDA$/) {
      $html .= "<li><b>IDA</b><br/> This PEG is Inferred from Direct Assay<br/><br/>";
    } elsif ($code =~ /^IGI$/) {
      $html .= "<li><b>IGI</b><br/> This PEG is Inferred from Genetic Interaction<br/><br/>";
    } elsif ($code =~ /^TAS$/) {
      $html .= "<li><b>TAS</b><br/> This PEG has a Traceable Author Statement<br/><br/>";
    }
  }

  # end the list
  $html .= "</ul>";

  # return the html string
  return $html;
}

=pod

=item * B<get_title> (fig_object, peg_id, no_ncbi)

Returns the Title including PEG name, Organism name and Taxonomy id

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<no_ncbi>: turns off the ncbi line, in default the line is displayed

=back

=cut

sub get_title {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $no_ncbi       = $parameters->{no_ncbi};
  my $ftype         = ($parameters->{ftype} || "Protein");
  my $user          = $parameters->{user} || '';

  # initialize html string
  my $title = "";
  my $viewer = "";
  my $subtitle = "";
  my $body = "";

  # get the organism name for this id
  my $organism = &org_of($fig_or_sprout, $peg);

  # check if the id fits the fig id format
  if ($peg =~ /^fig\|\d+\.\d+\.[a-z]+\./) {

    # check if the fig id exists
    if (! &is_real_feature($fig_or_sprout, $peg)) {
      $title = "<span class='title'>Sorry, $peg is an unknown identifier</span>";
    } else {

      $title = "<span class='title'>$ftype $peg: <i>$organism</i></span>";

      $viewer = "<BR /><A HRef='seedviewer.cgi?page=Annotation&feature=$peg&user=$user'>This feature in The SEED Viewer</A><BR />" if -f 'seedviewer.cgi';
      # check if the ncbi line is to be displayed
      unless (defined($no_ncbi)) {

	# parse the taxonomy id from the fig id
	my $taxon;
	if ($peg =~ /^fig\|(\d+)\.(\d+)/) {
	  $subtitle = "<span class='subtitle'>NCBI Taxonomy Id: <a href='http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=Info&id=$1&lvl=3&lin=f&keep=1&srchmode=1&unlock' target=_blank>$1</a></span>";
	}
      }
    }
  } else {
    # incorrect id passed, set error message
    $title = "<span class='title'>Illegal identifier passed: $peg</span>";
  }

  $body = join( "<BR />\n", $title, $viewer, $subtitle );

  # return data hash
  return { body     => $body,
	   title    => $title,
	   subtitle => $subtitle };
}

=pod

=item * B<get_current_assignment> (fig_object, peg_id)

Returns the current assignment of this peg.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=back

=cut

sub get_current_assignment {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # initialize html variable
  my $html = "";

  my $assignment = &trans_function_of($fig_or_sprout, $cgi, $peg);

  # check if assignment contains an ec number and link to kegg if it does
  $assignment =~ s/EC (\d+\.\d+\.\d+\.\d+)/<a href='http:\/\/www\.genome\.jp\/dbget-bin\/www_bget\?ec\:$1' target=_blank>EC $1<\/a>/g;

  $html = "<span class='headline'>Current Assignment: $assignment</span>";

  # return html string
  return $html;
}

=pod

=item * B<get_peg_view> (fig_object, peg_id, min, max, features)

Returns the graphic of the current PEG and it's neighborhood. If this
is the only block called, there is no need to pass min, max and features.
If you already know min, max and features, pass them to prohibit redundency.
You can get these values by calling the get_region_data function.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<min>: The number of the smallest base

=item * I<max>: The number of the largest base

=item * I<features>: The list of all features in this region

=back

=cut

sub get_peg_view {
    my ($parameters) = @_;

    # retrieve parameters from parameter hash
    my $fig_or_sprout = $parameters->{fig_object};
    my $peg           = $parameters->{peg_id};
    my $min           = $parameters->{min};
    my $max           = $parameters->{max};
    my $feat          = $parameters->{features};

    # generate the cgi object
    my $cgi = $parameters->{cgi} || new CGI();
    my $is_sprout = FIGRules::nmpdr_mode($cgi);

    # get user from cgi object
    my $user = $cgi->param('user') || '';

    # initialize html variable
    my $html = "";

    # determine min, max and list of features for this peg if they were not passed
    unless (defined($feat) && defined($min) && defined($max)) {
	($min, $max, $feat) = &get_region_data($parameters);

	# test if the action was successful, otherwise return error
	# Note that min = -1 on error, not zero -- GJO
	unless ($min > 0) {
	    return $max;
	}
    }

    # initialize genes variable
    my $genes;

    # what is this?
    my $in_cluster = &in_cluster_with($parameters);

    # pull some constant values outside of loop
    my $virt   = $cgi->param("48hr_job") ? "&48hr_job=" . $cgi->param("48hr_job") : '';
    my $sprout = $cgi->param('SPROUT')   ? "&SPROUT=1"                            : '';

    # iterate through the list of features
    foreach my $fid (@$feat) {

        # check if there is functional coupling
        my $fc = defined($in_cluster->{$fid}) ? 1 : "";

        # determine the uniprot id from the feature aliases
        my $aliases = join( ', ', &feature_aliasesL($fig_or_sprout,$fid) );
        my $uniprot = $aliases =~ /(uni[^,]+)/ ? $1 : '';

        # get the current contig, it's beginning and end
        my $locString = &feature_locationS($fig_or_sprout,$fid);
        my ($contig1, $beg1, $end1) = &boundaries_of($fig_or_sprout, $locString);
        Trace("Boundaries of $fid are $beg1 to $end1 for $locString.") if T(3);

        # determine the strand information
        my $strand = ($beg1 < $end1) ? "+" : "-";

        # get the function
        my $function = &function_ofS($fig_or_sprout, $fid, $user);

        # create info box for popup-tooltip
        my $info = join ('<br/>', "<b>PEG:</b> ".$fid,
                                  "<b>Contig:</b> ".$contig1,
                                  "<b>Begin:</b> ".$beg1,
                                  "<b>End:</b> ".$end1,
                                  $function ? "<b>Function:</b> ".$function : '',
                                  $uniprot ? "<b>Uniprot ID:</b> ".$uniprot : ''
                        );

        # determine color of the feature
        my $color = "";
        if     ($fid eq $peg)             { $color = "green" }  # current feature
        elsif  ($fc)                      { $color = "blue"  }  # coupled
        elsif  ($fid =~ /\.peg\.\d+$/)    { $color = "red"   }  # protein
        elsif  ($fid =~ /\.rna\.\d+$/)    { $color = "gray"  }  # RNA
        else                              { $color = 'black' }  # other feature

        # create a link to the protein page for this peg
        my $n;
        my $link = '';
        my $type = '';
        if ( $fid =~ /\.([a-zA-Z]+)\.(\d+)$/ )
        {
            $n = $2;
            $type = $1;
            if ( $type eq "peg" )
            {
                $link = "$FIG_Config::cgi_url/protein.cgi?prot=$fid&user=$user$virt$sprout";
            }
            else
            {
                $link = "$FIG_Config::cgi_url/feature.cgi?feature=$fid&user=$user$virt$sprout";
            }
        }

        # symbol shape   -- representing RNA as a rectangle is very poor
        my $shape;
        if    ( $type eq "peg" ) { $shape = ( $strand eq "+" ) ? "rightArrow" : "leftArrow" }
        elsif ( $type eq "rna" ) { $shape = ( $strand eq "+" ) ? "topArrow"   : "bottomArrow" }
        else                     { $shape = "Rectangle" }

        # create entry in the genes list containing the gathered information
        push(@$genes, [ &min($beg1,$end1), &max($beg1,$end1), $shape, $color, $n, $link, $info ]);
    }

    # having the genes list, call GenoGraphics to render the image
    # GenoGraphics takes a reference to a list of maps, so:
    my $map = ["",$min,$max,$genes];
    my $gg  = [$map];
    $html = join("", @{&GenoGraphics::render($gg,700,4,0,1)});

    # return html string
    return $html;
}

=pod

=item * B<get_compared_regions> (fig_object, peg_id, form_target, noheadline)

Returns an image of the compared regions along with forms to change the image and links to chromosomal clusters.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<form_target>: the script forms should have as their action parameter, default is frame.cgi

=item * I<noheadline>: if set to a true value, the function will not include a headline in the html string

=back

=cut

sub get_compared_regions {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $form_target   = $parameters->{form_target} || "frame.cgi";
  my $noheadline    = $parameters->{noheadline};

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # initialize html variable
  my $html = "";

  # create headline if wanted
  unless (defined($noheadline)) {

    $html .= "<a name=compared_regions></a><table><tr>";

    # retrieve url information from the cgi object
    my $url = $cgi->url(-relative => 1, -query => 1, -path_info => 1);

    # create a link to display/hide this information
    if (defined($cgi->param('compare_region'))) {
      $url =~ s/[&;]+compare_region=1//;
      $html .= "<td style='vertical-align: top; padding-right: 25px;'><input type=button value='hide' onclick='location=\"$url\"'></td>";
    } else {
      $html .= "<td style='vertical-align: top; padding-right: 25px;'><input type=button value='show' onclick='location=\"$url&compare_region=1#compared_regions\"'></td>";
    }

    $html .= "<td><h2>Compare Regions</h2></td></tr></table>";

    if ( -s 'seedviewer.cgi' )
    {
	# Add a link for the SeedViewer compared regions so that annotators can compare the two.
	# This is a temporary measure, and should be removed at some point.
	# Dec. 20, 2007. MJD

	# determine the user from the cgi object
	my $seed_user = $cgi->param('user') || '';
	$html .= "<a target=\"_blank\" href=\"seedviewer.cgi?page=Annotation&feature=$peg&user=$seed_user\"'>Compared Regions in SeedViewer</a><br>";
#	$html .= "<a target=\"_blank\" href=\"seedviewer.cgi?pattern=$peg&page=SearchResult&action=check_search&user=$user\"'>Compared Regions in SeedViewer</a><br>";
    }
  }

  # do not do the calculations unless requested
  if (defined($cgi->param('compare_region'))) {

    # check if the size of the region was passed, otherwise use default
    my $sz_region = $cgi->param('sz_region');
    $sz_region = $sz_region ? $sz_region : 16000;

    # check if the number of genomes to be displayed was passed, otherwise use default
    my $num_close = $cgi->param('num_close');
    $num_close = $num_close ? $num_close : 5;
    $parameters->{num_close} = $num_close;

    # determine the user from the cgi object
    my $user = $cgi->param('user') || '';

    # get a list of the closest PEGs
#    my @closest_pegs = &closest_pegs($parameters);

    $parameters->{closest_pegs} = []; #\@closest_pegs;

    # check if any pegs where returned
#    if (@closest_pegs > 0) {
    if ( 1 )
    {
#      Trace("Searching for closest pegs to $peg.") if T(3);
      # check if additional pegs should be added because they were truncated
#      if (&possibly_truncated($fig_or_sprout,$peg)) {
#	push(@closest_pegs,&possible_extensions($fig_or_sprout, $peg, \@closest_pegs));
#      }
#      Trace("Sorting by taxonomy.") if T(3);
#      # sort the closest PEGs according to taxonomy
#      $parameters->{closest_pegs} = \@closest_pegs;
#      @closest_pegs = &sort_fids_by_taxonomy($fig_or_sprout,@closest_pegs);
#      Trace("Taxonomy sort complete.") if T(3);
      # append the current peg to the list
#      unshift(@closest_pegs,$peg);

      use PinnedRegions;

      my $pin_desc = {
	               'pegs'                   => [$peg],
		       'collapse_close_genomes' => 0, 
		       'n_pch_pins'             => 0,
		       'n_sims'                 => $num_close,
		       'show_genomes'           => [],
		       'sim_cutoff'             => 1e-20,
		       'color_sim_cutoff'       => 1e-20,
		       'sort_by'                => 'phylogenetic_distance',
		       };

      my $fast_color  = 1;
      my $sims_from   = 'blast';
      my $region_size = $sz_region;
      my $maps = &PinnedRegions::pinned_regions($fig_or_sprout, $pin_desc, $fast_color, $sims_from, $region_size);

      my $gg = &transform($maps, $region_size);

      # initialize peg array
       my @all_pegs = ();

      my $color_sets = {};
       foreach my $map ( @$maps )
       {
 	  foreach my $feature ( @{ $map->{features} } )
 	  {
 	      if ( $feature->{type} eq 'peg' )
 	      {
 		  push @all_pegs, $feature->{fid};
		  
		  if ( $feature->{set_number} )
		  {
		      $color_sets->{$feature->{fid}} = $feature->{set_number} - 1;
		  }
 	      }
 	  }
       }

#       Trace("Building maps.") if T(3);
#       # build the data for rendering the image
#      my $gg_old = &build_maps($fig_or_sprout,\@closest_pegs,\@all_pegs,$sz_region, $form_target);
 
#       Trace("Processing colors.") if T(3);
#       # what does this do?
#       my $color_sets = &cluster_genes($fig_or_sprout,$cgi,\@all_pegs,$peg);
#      print "<pre>" . Dumper($color_sets) . "</pre>"; exit;
#       Trace("Genes clustered by color.") if T(3);
       &set_colors_text_and_links($gg,\@all_pegs,$color_sets);

#       Trace("Text links and colors set.") if T(3);
#       # check for sprout parameter
       my $sprout = $cgi->param('SPROUT') ? 1 : "";
#       Trace("Formatting results.") if T(3);
#       # what does this do?
      my($gene,$n,%how_many,$val,@vals,$x);
      my($i,$map);
      @vals = ();
      for ($i=(@$gg - 1); ($i >= 0); $i--) {
	my @vals1 = ();
	$map = $gg->[$i];
	my $found = 0;
	my $got_red = 0;
	undef %how_many;
	foreach $gene (@{$map->[3]}) {
	  if (($x = $gene->[3]) ne "grey") {
	    $n = $gene->[4];
	    if ($n == 1) {
	      $got_red = 1;
	    }
	    $how_many{$n}++;
	    $gene->[5] =~ /(fig\|\d+\.\d+\.peg\.\d+)/;
	    $val = join("@",($n,$i,$1,$map->[0]->[0],$how_many{$n}));
	    push(@vals1,$val);
	    $found++;
	  }
	}

	if (! $got_red) {
	  splice(@$gg,$i,1);
	} else {
	  push(@vals,@vals1);
	}
      }

      # check if there is more than one alignable genome, otherwise print error message
      if (@$gg < 2) {
	$html .= $cgi->h3("No alignable regions in close genomes");
      } else {

	# create a form to change the region size and number of displayed genomes
	$html .= $cgi->start_form(-action => "$FIG_Config::cgi_url/" . $form_target . "#compared_regions");
	my $param;

	# add all current parameters to the form as hidden values
	foreach $param ($cgi->param()) {
	  next if (($param eq "sz_region") || ($param eq "num_close"));
	  $html .= $cgi->hidden(-name => $param, -value => $cgi->param($param));
	}

	# generate the input fields of the form
	$html .= "size region: " . $cgi->textfield(-name => 'sz_region', -size =>  10, -value => $sz_region, -override => 1) . "&nbsp; &nbsp; &nbsp; &nbsp; &nbsp; " . "Number genomes: ". $cgi->textfield(-name => 'num_close', -size => 4, -value => $num_close, -override => 1) . $cgi->br . $cgi->submit('Resubmit');
	$html .= $cgi->end_form;

	# create a form to display the chromosomal clusters (opens in new window)
	my $ctarget = "_blank";
	$html .= $cgi->start_form(-target => $ctarget, -action => "$FIG_Config::cgi_url/chromosomal_clusters.cgi");
	$html .= $cgi->hidden(-name => 'SPROUT', -value => $sprout);
	$html .= $cgi->hidden(-name => "request", -value => "show_commentary");
	$html .= $cgi->hidden(-name => "prot", -value => $peg);
	$html .= $cgi->hidden(-name => "uni", -value => 1);
	$html .= $cgi->hidden(-name => "user", -value => $user);
	$html .= $cgi->hidden(-name => "show", -value => [@vals]);
	$html .= $cgi->submit('commentary');
	$html .= $cgi->end_form();

	# use GenoGraphics to render the image into the html string
	foreach (@{&GenoGraphics::render($gg,700,4,0,2)}) {
	  $html .= $_;
	}

	# get previous and next link
	my($prev,$next);
	my $map1 = $gg->[0]->[3];
	if (($map1->[0]->[5] =~ /(fig\|\d+\.\d+\.peg\.\d+)/) && ($1 ne $peg)) {
	  $prev = $1;
	}
	if (($map1->[$#{$map1}]->[5] =~ /(fig\|\d+\.\d+\.peg\.\d+)/) && ($1 ne $peg)) {
	  $next = $1;
	}
	$parameters->{prev} = $prev;
	$parameters->{next} = $next;
	$html .= &get_prev_next_link($parameters);
      }

    } else {

      # no regions in close genomes found, set the message
      $html .= "<span class='message'>No alignable regions in close genomes</span>";
    }
    Trace("Compare regions complete.") if T(3);
  }
  return $html;
}

sub transform {
    my($maps, $region_size) = @_;

    # transform 'PinnedRegions' data in $maps to format used by GenoGraphics
    my $gg = [];

    foreach my $region ( @$maps )
    {
	my $genome_name = $region->{org_name};
	my $contig      = $region->{contig};

	# Need to flip regions with pinned PEG on minus strand, i.e. display the region
	# with this PEG on the plus strand
	my $flip        = ($region->{pinned_peg_strand} eq '-')? 1 : 0;

	# Location on contig
	my $reg_beg     = $region->{beg};
	my $reg_end     = $region->{end};

	# Location on image region
	my $reg_start = 0;
	my $reg_stop  = $region_size;

	my $short_name = $genome_name;
	$short_name =~ s/^(\w)\S+/$1\./;
	$short_name = substr($short_name, 0, 15);

	my $popup_text = "Genome: $genome_name<br>Contig: $contig";

	my $gg_region = [[$short_name, undef, $popup_text, undef, 'Contig'], $reg_start, $reg_stop];

	my $region_features = [];

	foreach my $feature ( @{ $region->{features} } )
	{
	    my $fid = $feature->{fid};

	    # Location on contig
	    my $feat_beg = $feature->{beg};
	    my $feat_end = $feature->{end};

	    # Map location on contig to image location
	    my $feat_start = &map_coords($feat_beg, $reg_beg, $reg_end, $flip);
	    $feat_start    = &bring_into_region($feat_start, $reg_start, $reg_stop);

	    my $feat_stop  = &map_coords($feat_end, $reg_beg, $reg_end, $flip);
	    $feat_stop     = &bring_into_region($feat_stop, $reg_start, $reg_stop);

	    my($start, $stop) = sort {$a <=> $b} ($feat_start, $feat_stop);

	    my $shape      = &shape($feat_beg, $feat_end, $flip);
	    
	    my $color = 'grey';
	    my $set_number = $feature->{set_number};

#	    my $url = qq(protein.cgi?user=;compare_region=1&amp;prot=$fid&amp;compare_region=1\#compared_regions);
	    my $url = $fid;

	    my $text = qq(<b>PEG:</b> $fid<br>) .
		       qq(<b>Contig:</b> $contig<br>) .
		       qq(<b>Begin:</b> $feat_beg<br>) .
		       qq(<b>End:</b> $feat_end<br>) .
		       qq(<b>Function:</b> $feature->{function});

	    
	    my $link = qq(<a href="protein.cgi?compare_region=1&amp;num_close=&amp;prot=$fid&amp;user=#compared_regions">show</a>);

	    push @$region_features, [$start, $stop, $shape, $color, $set_number, $url, $text, $link];
	}
	
	push @$gg_region, $region_features;

	push @$gg, $gg_region;
    }

    return $gg;
}

sub bring_into_region {
    my($x, $reg_start, $reg_stop) = @_;
    
    if ( $x < $reg_start ) {
	$x = $reg_start;
    } elsif ( $reg_stop < $x ) {
	$x = $reg_stop;
    }

    return $x;
}

sub map_coords {
    my($x, $reg_beg, $reg_end, $flip) = @_;
    my $y;

    if ( $flip ) {
	$y = $reg_end - $x + 1;
    } else {
	$y = $x - $reg_beg + 1;
    }

    return $y;
}

sub shape {
    my($beg, $end, $flip) = @_;
    my $shape;

    if ( $beg <= $end ) {
	$shape = $flip? 'leftArrow' : 'rightArrow';
    } else {
	$shape = $flip? 'rightArrow' : 'leftArrow';
    }
    
    return $shape;
}

=pod

=item * B<get_sims_request_form> (fig_object, peg_id, short_form, form_target)

Returns a form to request similarities for the current PEG.

=over 2

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<short_form>: true value indicates the short version of the form, false the long version. Default is false.

=item * I<form_target>: the script forms have as their action parameter, default is frame.cgi

=back

=cut

sub get_sims_request_form {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $short_form    = $parameters->{short_form};
  my $form_target   = $parameters->{form_target} || "frame.cgi";

  # generate the cgi object
  my $cgi = $parameters->{cgi} || new CGI();
  my $sprout = $cgi->param('SPROUT') || 0;

  # initialize html string
  my $html = "";

  # retrieve username from the current cgi object
  my $user = $cgi->param("user");

  # check for translation status
  my $trans_role = $cgi->param('translate') ||  0;

  # get the parameters for the similarities calculation
  my $params = &get_similarity_parameters($cgi);

  my $maxN            = $params->{maxN};
  my $max_expand      = $params->{max_expand};
  my $maxP            = $params->{maxP};
  my $select          = $params->{select};
  my $show_env        = $params->{show_env};
  my $show_alias      = $params->{show_alias};
  my $sort_by         = $params->{sort_by};
  my $group_by_genome = $params->{group_by_genome};
  my $expand_groups   = $params->{expand_groups};

  #  New similarity options

  #  Act on request for more or fewer sim options
  my $extra_opt = defined( $cgi->param('extra_opt') ) ? $cgi->param('extra_opt') : 0;
  if ( $cgi->param('more sim options') ) {
    $extra_opt = 1;
    $cgi->delete('more sim options');
  }
  if ( $cgi->param('fewer sim options') ) {
    $extra_opt = 0;
    $cgi->delete('fewer sim options');
  }

  #  Make defaults completely open (match original behavior)
  my $min_sim   = $extra_opt && defined( $cgi->param('min_sim') )   ? $cgi->param('min_sim')   : 0;
  my $sim_meas  = $extra_opt && defined( $cgi->param('sim_meas') )  ? $cgi->param('sim_meas')  : 'id';
  my $min_q_cov = $extra_opt && defined( $cgi->param('min_q_cov') ) ? $cgi->param('min_q_cov') : 0;
  my $min_s_cov = $extra_opt && defined( $cgi->param('min_s_cov') ) ? $cgi->param('min_s_cov') : 0;

  #  New parameters.  Not yet implimented.
  #  The defaults for representative sequences might be tuned:
  my $show_rep  = $extra_opt && defined( $cgi->param('show_rep') )  ? $cgi->param('show_rep')  : 0;
  my $max_sim   = $extra_opt && defined( $cgi->param('max_sim') )   ? $cgi->param('max_sim')   : 0.70;
  my $dyn_thrsh = $extra_opt && defined( $cgi->param('dyn_thrsh') ) ? $cgi->param('dyn_thrsh') : 0;
  my $save_dist = $extra_opt && defined( $cgi->param('save_dist') ) ? $cgi->param('save_dist') : 0.80;

  #  Mark some of the sequences automatically?
  my $chk_which = $extra_opt && defined( $cgi->param('chk_which') ) ? $cgi->param('chk_which')  : 'none';

  #  Use $cgi->param('more similarities') to drive increase in maxN and max_expand
  if ( $cgi->param('more similarities') ) {
    $maxN       *= 2;
    $max_expand *= 2;
    $cgi->delete('more similarities');
  }

  #  Sanity checks on fixed vocabulary parameter values:
  my %select_opts    = map { ( $_, 1 ) } qw( all  fig  figx  fig_pref  figx_pref );
  my %sort_opts      = map { ( $_, 1 ) } qw( bits  id  id2  bpp  bpp2 );
  my %sim_meas_opts  = map { ( $_, 1 ) } qw( id  bpp );
  my %chk_which_opts = map { ( $_, 1 ) } qw( none  all  rep );

  $select    = 'figx' unless $select_opts{ $select };   # Make the default, FIG only
  $sort_by   = 'bits' unless $sort_opts{ $sort_by };
  $sim_meas  = 'id'   unless $sim_meas_opts{ $sim_meas };
  $chk_which = 'none' unless $chk_which_opts{ $chk_which };

  #  We have processed all options.  Use them to build forms.

  #  Checkmarks for input tags
  my $chk_select_all   = select_if( $select eq 'all' );
  my $chk_select_figp  = select_if( $select eq 'fig_pref' );
  my $chk_select_figxp = select_if( $select eq 'figx_pref' );
  my $chk_select_fig   = select_if( $select eq 'fig' );
  my $chk_select_figx  = select_if( $select eq 'figx' );
  my $chk_show_env     = chked_if(  $show_env );
  my $chk_show_alias   = chked_if(  $show_alias );
  my $chk_gbg          = chked_if(  $group_by_genome );
  my $chk_sort_by_id   = select_if( $sort_by eq 'id' );
  my $chk_sort_by_id2  = select_if( $sort_by eq 'id2' );
  my $chk_sort_by_bits = select_if( $sort_by eq 'bits' );
  my $chk_sort_by_bpp  = select_if( $sort_by eq 'bpp' );
  my $chk_sort_by_bpp2 = select_if( $sort_by eq 'bpp2' );

  my $envCheckBox  = "";
  my $typeSelector = "<select name=select>\n";
  if ($sprout) {
    $typeSelector .= "<option value=fig  $chk_select_fig>to max exp</option>\n" .
                     "<option value=figx $chk_select_fig>all</option>\n";
  } else {
    $typeSelector .= "<option value=all       $chk_select_all>Show all databases</option>\n" .
                     "<option value=fig_pref  $chk_select_figp>Prefer FIG IDs (to max exp)</option>\n" .
                     "<option value=figx_pref $chk_select_figxp>Prefer FIG IDs (all)</option>\n" .
                     "<option value=fig       $chk_select_fig>Just FIG IDs (to max exp)</option>\n" .
                     "<option value=figx      $chk_select_figx>Just FIG IDs (all)</option>\n";
    $envCheckBox = "Show Env. samples:<input type=checkbox name=show_env value=1 $chk_show_env> &nbsp;&nbsp;";
  }
  $typeSelector .= "</select> &nbsp;&nbsp;\n";

  my $jobid = $cgi->param("48hr_job");

  #  Put in come common features of forms:

  $html .= <<"Common_Part_1";

<FORM Action="$form_target#Similarities">
    <input type=hidden name=prot      value="$peg">
    <input type=hidden name=sims      value=1>
    <input type=hidden name=fid       value="$peg">
    <input type=hidden name=user      value="$user">

    Max sims:<input type=text name=maxN size=5 value=$maxN> &nbsp;&nbsp;
    Max expand:<input type=text name=max_expand size=5 value=$max_expand> &nbsp;&nbsp;
    Max E-val:<input type=text name=maxP size=8 value=$maxP> &nbsp;&nbsp;
    $typeSelector
    $envCheckBox
    Show aliases:<input type=checkbox name=show_alias value=1 $chk_show_alias><br />

Common_Part_1

  #  Some conditional parameters

  $html .= qq(    <input type=hidden name=translate value="$trans_role">\n) if $trans_role;
  $html .= qq(    <input type=hidden name=SPROUT    value="$sprout">\n)     if $sprout;
  $html .= qq(    <input type=hidden name=48hr_job  value="$jobid">\n)      if $jobid;

  #  Two complex input elements

  my $sort_menu = <<"End_of_Sort";
Sort by
    <select name=sort_by>
	<option value=bits $chk_sort_by_bits>score</option>
	<option value=id2  $chk_sort_by_id2>percent identity*</option>
	<option value=bpp2 $chk_sort_by_bpp2>score per position*</option>
	<option value=id   $chk_sort_by_id>percent identity</option>
	<option value=bpp  $chk_sort_by_bpp>score per position</option>
    </select> &nbsp;&nbsp;
End_of_Sort

  my $gbg_checkbox = <<"End_of_GBG";
<!-- The actual value is in group_by_genome.value, so that 'false' can be actively maintained -->
    <input type=hidden name=group_by_genome value=$group_by_genome>
    Group by genome:<input type=checkbox name=gbgb value=1 $chk_gbg onClick="var gbg=this.form.group_by_genome; var x=gbg.value==0; self.checked=x; gbg.value=x?1:0; return true">
End_of_GBG

  #  Distinguishing features of short and long forms:

  if ( $short_form ) {

    $html .= <<"End_Short_Form";
    <input type=submit name=Similarities value=Similarities> &nbsp;&nbsp;
    $sort_menu
    $gbg_checkbox
</FORM>

End_Short_Form

  } else {
    #  Navigation buttons
    my $opts = { fid => $peg, type => 'peg' };
    my $prev_peg_btn = $fig_or_sprout->previous_feature( $opts ) ? $cgi->submit('previous PEG') : '';
    my $next_peg_btn = $fig_or_sprout->next_feature( $opts )     ? $cgi->submit('next PEG')     : '';

    #  Add/remove extra options button
    my $extra_opt_btn = $extra_opt ? $cgi->submit('fewer sim options') : $cgi->submit('more sim options');

    #  Checkmarks for input tags
    my $chk_sim_meas_id  = select_if( $sim_meas eq 'id' );
    my $chk_sim_meas_bpp = select_if( $sim_meas eq 'bpp' );
    my $chk_show_rep     = chked_if( $show_rep );
    my $chk_dyn_thrsh    = chked_if( $dyn_thrsh );
    my $chk_chk_none     = select_if( $chk_which eq 'none' );
    my $chk_chk_all      = select_if( $chk_which eq 'all' );
    my $chk_chk_rep      = select_if( $chk_which eq 'rep' );

    # write form
    $html .= <<"End_Default_Options";

    $sort_menu
    $gbg_checkbox<br />
End_Default_Options

    #  Extra options
    $html .= <<"End_Extra_Options" if $extra_opt;
    <input type=hidden name=extra_opt value=\"$extra_opt\">

    Min similarity:<input type=text name=min_sim size=5 value=$min_sim>
    defined by
    <select name=sim_meas>
	<option value=id  $chk_sim_meas_id>identities (0-100%)</option>
	<option value=bpp $chk_sim_meas_bpp>score per position (0-2 bits)</option>
    </select> &nbsp;&nbsp;
    Min query cover (%):<input type=text name=min_q_cov size=5 value=$min_q_cov> &nbsp;&nbsp;
    Min subject cover (%):<input type=text name=min_s_cov size=5 value=$min_s_cov><br />

    <!--  Hide unimplimented options
    <TABLE Cols=2>
        <TR>
            <TD Valign=top><input type=checkbox name=show_rep $chk_show_rep></TD>
            <TD> Show only representative sequences whose similarities to one another
                are less than <input type=text size=5 name=max_sim value=$max_sim>
                <br />
                <input type=checkbox name=dyn_thrsh value=1 $chk_dyn_thrsh> But keep sequences
                that are at least <input type=text size=5 name=save_dist value=$save_dist>
                times as distant from one another as from the query</TD>
        </TR>
    </TABLE>

    <input type=hidden name=chk_which value=\"$chk_which\">

    Automatically Select (check) which sequences:<select name=chk_which>
	<option value=none $chk_chk_none>none</option>
	<option value=all  $chk_chk_all>all shown</option>
	<option value=rep  $chk_chk_rep>representative set</option>
    </select><br />
    -->
End_Extra_Options

    #  Submit buttons
    $html .= <<"End_of_Buttons";
    <input type=submit name='resubmit' value='resubmit'>
    <input type=submit name='more similarities' value='more similarities'>
    $prev_peg_btn
    $next_peg_btn
    $extra_opt_btn
</FORM>

End_of_Buttons

  }

  # return html string
  return $html;
}

###
###
### NEED TO BE DONE STILL
###
###

sub view_annotations {
    my($fig_or_sprout,$cgi,$prot) = @_;

    my $html = "";
    my $col_hdrs = ["who","when","annotation"];
    my $tab = [ map { [$_->[2],$_->[1],"<pre>" . $_->[3] . "<\/pre>"] } &feature_annotations($fig_or_sprout,$cgi,$prot) ];
    if (@$tab > 0) {
      $html .= &HTML::make_table($col_hdrs,$tab,"Annotations for $prot");
    } else {
      $html .= "<h1>No Annotations for $prot</h1>\n";
    }

    return $html;
}

sub view_all_annotations {
    my($fig_or_sprout,$cgi,$peg) = @_;
    my($ann);

    my $html = "";
    if (&is_real_feature($fig_or_sprout,$peg)) {
      my $col_hdrs = ["who","when","PEG","genome","annotation"];
      my @related  = &related_by_func_sim($fig_or_sprout,$cgi,$peg,$cgi->param('user'));
      push(@related,$peg);

      my @annotations = &merged_related_annotations($fig_or_sprout,\@related);

      my $tab = [ map { $ann = $_;
			[$ann->[2],$ann->[1],&HTML::fid_link($cgi,$ann->[0]),
			 &genus_species($fig_or_sprout,&genome_of($ann->[0])),
			 "<pre>" . $ann->[3] . "</pre>"
			] } @annotations];
      if (@$tab > 0) {
	$html .= &HTML::make_table($col_hdrs,$tab,"All Related Annotations for $peg");
      } else {
	$html .= "<h1>No Annotations for $peg</h1>\n";
      }
    }

    return $html;
}

sub make_assignment {
    my($fig_or_sprout,$cgi,$prot) = @_;
    my($userR);

    my $function = $cgi->param('func');
    my $user     = $cgi->param('user');

    if ($function && $user && $prot) {
        #  Everyone is master, and assign_function adds annotation:
        #
        # if ($user =~ /master:(.*)/) {
	    # 	$userR = $1;
	    # 	&assign_function($fig_or_sprout,$prot,"master",$function,"");
	    # 	&add_annotation($fig_or_sprout,$cgi,$prot,$userR,"Set master function to\n$function\n");
        # } else {

	    $fig_or_sprout->assign_function( $prot, $user, $function, "" );

	    # &add_annotation($fig_or_sprout,$cgi,$prot,$user,"Set function to\n$function\n");
    }
    $cgi->delete("request");
    $cgi->delete("func");

    return 1;
}

sub show_abstract_coupling_evidence {
    my($fig_or_sprout,$cgi,$prot) = @_;

    my $html = "";

    my @coupling = $fig_or_sprout->abstract_coupled_to($prot);
    if (@coupling > 0) {
      $html .= &HTML::abstract_coupling_table($cgi,$prot,\@coupling);
    } else {
      $html .= $cgi->h1("sorry, no abstract coupling data for $prot");
    }

    return $html;
}

sub show_coupling_evidence {
  my($fig_or_sprout,$cgi,$peg) = @_;
  my($pair,$peg1,$peg2,$link1,$link2);

  my $html = "";

  my $user = $cgi->param('user');
  my $to   = $cgi->param('to');
  my @coup = grep { $_->[1] eq $to } &coupling_and_evidence($fig_or_sprout,$peg,5000,1.0e-10,4,1);

  if (@coup != 1) {
    $html .= "<h1>Sorry, no evidence that $peg is coupled to $to</h1>\n";
  } else {
    my $col_hdrs = ["Peg1","Function1","Peg2","Function2","Organism"];
    my $tab = [];
    foreach $pair (@{$coup[0]->[2]}) {
      ($peg1,$peg2) = @$pair;
      $link1 = &HTML::fid_link($cgi,$peg1);
      $link2 = &HTML::fid_link($cgi,$peg2);
      push( @$tab, [ $link1,
		     scalar &function_ofS($fig_or_sprout,$peg1,$user),
		     $link2,
		     scalar &function_ofS($fig_or_sprout,$peg2,$user),
		     &org_of($fig_or_sprout,$peg1)
		   ]
	  );
    }
    $html .= &HTML::make_table($col_hdrs,$tab,"Evidence that $peg Is Coupled To $to");
  }

  return $html;
}

sub show_ec_to_maps {
    my($fig_or_sprout,$cgi,$ec) = @_;

    my $html = "";

    $ec = $cgi->param('ec');
    if (! $ec) {
        push(@$html,$cgi->h1("Missing EC number"));
        return;
    }

    my @maps = &ec_to_maps($fig_or_sprout,$ec);
    if (@maps > 0) {
        my $col_hdrs = ["map","metabolic topic"];
        my $map;
        my $tab      = [map { $map = $_; [&map_link($cgi,$map),&map_name($fig_or_sprout,$map)] } @maps];
        $html .= &HTML::make_table($col_hdrs,$tab,"$ec: " . &ec_name($fig_or_sprout,$ec));
    }

    return $html;
}

sub link_to_map {
    my($fig_or_sprout,$cgi) = @_;

    my $html = "";

    my $map = $cgi->param('map');
    if (! $map) {
        $html .= $cgi->h1("Missing Map");
        return $html;
    }

    my $org = $cgi->param('org');
    if (! $org) {
        $html .= $cgi->h1("Missing Org Parameter");
        return;
    }
    my$user = $cgi->param('user');
    $user = $user ? $user : "";

    $ENV{"REQUEST_METHOD"} = "GET";
    $ENV{"QUERY_STRING"} = "user=$user&map=$map&org=$org";
    my @out = `./show_kegg_map.cgi`;
    &HTML::trim_output(\@out);
    foreach (@out) {
      $html .= $_;
    }

    return $html;
}

sub show_fusions {
    my($fig_or_sprout,$cgi,$prot) = @_;

    my $user = $cgi->param('user');
    $user = $user ? $user : "";
    my $sprout = $cgi->param('SPROUT') ? '&SPROUT=1' : "";

    $ENV{"REQUEST_METHOD"} = "GET";
    $ENV{"QUERY_STRING"} = "peg=$prot&user=$user$sprout";
    my @out = `./fusions.cgi`;
    print join("",@out);
    return 1;
}

sub map_link {
    my($cgi,$map) = @_;

    $cgi->delete('request');
    my $url  = $cgi->url(-relative => 1, -query => 1, -path_info => 1) . "&request=link_to_map&map=$map";
    my $link = "<a href=\"$url\">$map</a>";
    return $link;
}

###
###
###
###
###

###
#
# href link functions
#
###

=pod

=item * B<get_prev_next_link> (fig_object, peg_id, form_target)

Returns an HTML link to the previous and next PEG

=item * I<fig_object>: a reference to a fig object

=item * I<peg_id>: the id of the PEG in question

=item * I<form_target>: the script forms should have as their action parameter, default is frame.cgi

=back

=cut

sub get_prev_next_link {
  my ($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $form_target   = $parameters->{form_target} || "frame.cgi";
  my $prev          = $parameters->{prev};
  my $next          = $parameters->{next};

  # get cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # Get the sprout flag.
  my $sproutFlag = (FIGRules::nmpdr_mode($cgi) ? '&SPROUT=1' : '');

  my $user = $cgi->param('user');
  my $sz_region = $cgi->param('sz_region') || 16000;
  my $num_close = $cgi->param('num_close') || 5;

  # initialize html variable
  my $html = "<table><tr>";

  if (defined($prev)) {
    $html .= "<td><a href='$form_target?prot=$prev&compare_region=1&user=$user&sz_region=$sz_region$sproutFlag&num_close=$num_close#compared_regions'><< previous</a></td>";
  }

  my $genome = &FIG::genome_of($peg);
  my @contigs = $fig_or_sprout->contigs_of($genome);
  my @loc = $fig_or_sprout->feature_location($peg);
  my $contig;
  if ((@loc > 0) && ($loc[0] =~ /^(\S+)_\d+_\d+$/)) {
    $contig = $1;
  }
  my $i;
  for ($i=0; ($i < @contigs) && ($contig ne $contigs[$i]); $i++) {}
  if (($i > 0) && ($i < @contigs)) {

    unless (defined($prev)) {

      # get previous contig
      $contig = $contigs[$i-1];

      my($genes,undef,undef) = $fig_or_sprout->genes_in_region($genome,$contig,1,10000);
      my @genes = grep { $fig_or_sprout->ftype($_) eq "peg" } @$genes;

      if (@genes > 0) {
	my $gene = $genes[0];
	$html .= "<td><a href='$form_target?prot=$gene&compare_region=1&user=$user&sz_region=$sz_region$sproutFlag&num_close=$num_close#compared_regions'><< previous</a></td>";
      }
    }

    unless (defined($next)) {

      # get next contig
      $contig = $contigs[$i+1];

      my($genes,undef,undef) = $fig_or_sprout->genes_in_region($genome,$contig,1,10000);
      my @genes = grep { $fig_or_sprout->ftype($_) eq "peg" } @$genes;

      if (@genes > 0) {
	my $gene = $genes[0];
	$html .= "<td style='width: 700px;'></td><td><a href='$form_target?prot=$gene&compare_region=1&user=$user&sz_region=$sz_region$sproutFlag&num_close=$num_close#compared_regions'>next >></a></td>";
      }
    }

  }

  if (defined($next)) {
    $html .= "<td style='width: 700px;'></td><td><a href='$form_target?prot=$next&compare_region=1&user=$user&sz_region=$sz_region$sproutFlag&num_close=$num_close#compared_regions'>next >></a></td>";
  }

  $html .= "</tr></table>";

  # return the html string
  return $html;
}

=pod

=item * B<get_evidence_codes_link> ()

Returns an HTML link to the evidence codes explanation page

=back

=cut

sub get_evidence_codes_link {

  return "<A href=\"Html/evidence_codes.html\" target=\"help\">Ev</A>";
}

=pod

=item * B<get_index_link> ()

Returns an HTML link to the index.cgi page

=back

=cut

sub get_index_link {

  # get cgi object
  my $cgi = new CGI();

  # get username from cgi object
  my $user = $cgi->param('user');

  # return the link
  return "<A href=\"index.cgi?user=$user\">FIG search</A>";
}

=pod

=item * B<get_translation_link> ()

Returns a link that toggles the status of the translation on/off

=back

=cut

sub get_translation_link {
    # get the current cgi object
    my $cgi  = new CGI();

    # initialize return html string
    my $html = "";

    # initialize status variable
    my $msg;

    # retrieve url information from the cgi object
    my $url = $cgi->url(-relative => 1, -query => 1, -path_info => 1);

    # if translation param is true, set it to false in the link
    if ($cgi->param('translate')) {
        $url =~ s/[;&]translate(=[^;&])?//i or $url =~ s/translate(=[^;&])?[;&]//i;
        $msg = "Turn Off Function Translation";
    } else {
	# otherwise set it to true
        $url .= "&translate=1";
        $msg = "Translate Function Assignments";
    }

    # compose the href, this could be turned into a button with onClick event
    $html = "<a href=\"$url\">$msg</a><br>\n";

    # return html string
    return $html;
}

=pod

=item * B<get_evidence_link> ()

Returns a link that toggles the status of the translation on/off

=back

=cut

sub get_evidence_link {
    my($neigh,$sc) = @_;

    # get the CGI object
    my $cgi = new CGI();

    # initialize html string
    my $html = "";

    # retrieve the neccessary cgi paramters
    my $prot   = $cgi->param('prot');
    my $sprout = $cgi->param('SPROUT') ? "&SPROUT=1" : '';
    my $user   = $cgi->param('user') || '';

    # construt the link
    my $link = "$FIG_Config::cgi_url/protein.cgi?prot=$prot&user=$user&request=show_coupling_evidence&to=$neigh$sprout";
    $html = "<a href=$link>$sc</a>";

    # return the html
    return $html;
}

sub pin_link {
    my($cgi,$peg) = @_;
    my $user = $cgi->param('user');
    $user = defined($user) ? $user : "";

    my $sprout = $cgi->param('SPROUT') ? "&SPROUT=1" : "";
    my $cluster_url  = "chromosomal_clusters.cgi?prot=$peg&user=$user&uni=1$sprout";

    my $cluster_img = 0 ? "*" : '<img src="Html/button-pins-1.png" border="0">';
    my $cluster_link = "<a href=\"$cluster_url\" target=_blank>$cluster_img</a>";
    return $cluster_link;
}

sub set_tc_link {
    my($fig_or_sprout,$org,$tc) = @_;

    if ($tc =~ /^TC\s+(\S+)$/)
    {
        return "<a href='http://www.tcdb.org/tcdb/index.php?tc=$1&Submit=Lookup' target=_blank>$tc</a>";
    }
    return $tc;
}

sub set_ec_to_maps {
    my($fig_or_sprout,$org,$ec,$cgi) = @_;

    my @maps = &ec_to_maps($fig_or_sprout,$ec);
    if (@maps > 0) {
        $cgi->delete('request');
        my $url  = $cgi->url(-relative => 1, -query => 1, -path_info => 1) . "&request=ec_to_maps&ec=$ec&org=$org";
        my $link = "<a href=\"$url\">$ec</a>";
        return $link;
    }
    return $ec;
}

sub peg_url {
    my($cgi,$peg) = @_;

    my $prot = $cgi->param('prot');
    $cgi->delete('prot');
    my $url  = $cgi->url(-relative => 1, -query => 1, -path_info => 1) . "&prot=$peg&compare_region=1#compared_regions";
    $cgi->delete('prot');
    $cgi->param(-name => 'prot', -value => $prot);

    return $url;
}

sub assign_link {
    my($cgi,$func,$existing_func) = @_;
    my($assign_url,$assign_link);

    if ($func && ((! $existing_func) || ($existing_func ne $func))) {
        $cgi->delete('request');
        $assign_url  = $cgi->url(-relative => 1, -query => 1, -path_info => 1) . "&request=fast_assign&func=$func";
        $assign_link = "<a href=\"$assign_url\">&nbsp;<=&nbsp;</a>";
    } else {
        $assign_link = "&nbsp;";
    }
    return $assign_link;
}

###
#
# Data Generation Methods
#
# These Methods are for internal use only, so they are not POD
#
###

sub get_identical_protein_data {
  my($parameters) = @_;

  # retrieve parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};

  # get the current cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # initialize some variables
  my($who,$func,$ec,@ecs,@tmp,$id,$i,$master_func,$user_func,$x);

  # get the current user
  my $user = $cgi->param('user');
  $user = defined($user) ? $user : "";

  # initialize data hash
  my $data;

  my @funcs;
  $user_func = &trans_function_of($fig_or_sprout, $cgi, $peg);

  my @maps_to  = grep { $_ ne $peg and $_ !~ /^xxx/ } map { $_->[0] } &mapped_prot_ids($fig_or_sprout,$cgi,$peg);

  foreach $id (@maps_to) {
    my $tmp;
    if (($id ne $peg) && ($tmp = &trans_function_of($fig_or_sprout, $cgi, $id))) {
      push(@funcs, [$id,&who($id),$tmp]);
    }
  }
  @funcs = map { ($_->[1] eq "master") ? [$_->[0],"",$_->[2]] : $_ } @funcs;

  # create an array of hashes containing the data
  my $rows = [ map { ($id,$who,$func) = @$_;
		     { id         => &HTML::set_prot_links($cgi,$id),
		       organism   => &org_of($fig_or_sprout,$id) || "&nbsp;",
		       who        => $who ? $who : "&nbsp;",
		       assign     => $user ? &assign_link($cgi,$func,$user_func) : "&nbsp;",
		       assignment => &set_ec_and_tc_links($fig_or_sprout,&genome_of($peg),$func)} } @funcs ];

  # return the data array
  return $rows;
}

sub get_similarity_parameters {
  # get current CGI object
  my $cgi = new CGI();

  #  Read available parameters, and fill in defaults:
  my $maxN            = defined( $cgi->param('maxN') )            ? $cgi->param('maxN')            : 100;
  my $max_expand      = defined( $cgi->param('max_expand') )      ? $cgi->param('max_expand')      :   5;
  my $maxP            = defined( $cgi->param('maxP') )            ? $cgi->param('maxP')            :   1.0e-5;
  my $select          = $cgi->param('select')                    || 'figx';
  my $show_env        = $cgi->param('show_env')                  ||  0;
  my $show_alias      = defined( $cgi->param('show_alias') )      ? $cgi->param('show_alias')      :   0;
  my $sort_by         = $cgi->param('sort_by')                   || 'bits';
  my $group_by_genome = ( defined( $cgi->param('group_by_genome') ) && ! $cgi->param('group_by_genome') ) ? 0 : 1;
  my $expand_groups   = $cgi->param('expand_groups')             ||  0;

  # create the parameters hash to return
  my $parameters = { maxN            => $maxN,
                     max_expand      => $max_expand,
                     maxP            => $maxP,
                     select          => $select,
                     show_env        => $show_env,
                     show_alias      => $show_alias,
                     sort_by         => $sort_by,
                     group_by_genome => $group_by_genome,
                     expand_groups   => $expand_groups
                   };

  # return parameters hash
  return $parameters;
}

sub set_colors_text_and_links {
    my($gg,$all_pegs,$color_sets) = @_;
    my($map,$gene,$peg,$color);

    my $cgi = new CGI();

    foreach $map (@$gg) {
#	print "<pre>" . Dumper($map) . "</pre>";
        foreach $gene (@{$map->[3]}) {
#	print "<pre>" . Dumper($gene) . "</pre>"; exit;
            $peg = $gene->[5];
            if (defined($color = $color_sets->{$peg})) {
                $gene->[3] = ($color == 0) ? "red" : "color$color";
                $gene->[4] = $color + 1;
            }
            $gene->[5] = &peg_url($cgi,$peg);
        }
    }
}

=head3 get_bbhs

    my $html = SeedComponents::Protein::get_bbhs($parameters);

Return a button for retrieving bidirectional best hits, or-- if the user wants
to see the hits-- return a table of the hits themselves.

The parameter hash should contain the following fields.

=over 4

=item fig

FIG-like object for accessing the data store.

=item peg_id

ID of the feature that has the focus.

=item RETURN

Returns the HTML to display the button or the table.

=back

=cut

sub get_bbhs {
    # Get the parameters.
    my ($parameters) = @_;

    # Declare the return variable.
    my $retVal = "";
    my $fig_or_sprout = $parameters->{fig_object};
    my $peg = $parameters->{peg_id};
    my $cgi = $parameters->{cgi} || new CGI();

    if (! $cgi->param('bbhs')) {
        $retVal = sprout_bbhs_request_form($parameters);
    } else {
        my $html = [];
        my $user = $cgi->param('user') || "";
        my $id = $parameters->{id} || "sprout_bbh_results";
        $parameters->{id} = $id;
        my $title = $parameters->{title} || "Bidirectional Best Hits";
        $parameters->{initial_value} = "expanded";
        my $current_func = &trans_function_of($fig_or_sprout,$cgi,$peg);
        push @$html, "<div id=\"${id}_content\" class=\"showme\">";
        push( @$html, $cgi->hr,
                      "<a name=Similarities>",
                      $cgi->h1(''),
                      "</a>\n"
            );

        my @sims = sort { $a->[1] <=> $b->[1] } $fig_or_sprout->bbhs($peg,1.0e-10);

        my @from = $cgi->radio_group(-name => 'from',
                                     -nolabels => 1,
                     -override => 1,
                                     -values => ["",$peg,map { $_->[0] } @sims]);

        my $target = "_blank";
            # RAE: added a name to the form so tha the javascript works
        push( @$html, $cgi->start_form( -method => 'post',
                        -target => $target,
                        -action => 'fid_checked.cgi',
                        -name   => 'fid_checked'
                        ),
                  $cgi->hidden(-name => 'SPROUT', -value => 1),
                  $cgi->hidden(-name => 'fid', -value => $peg),
                  $cgi->hidden(-name => 'user', -value => $user),
                  $cgi->br,
                      "For Selected (checked) sequences: ",
                  $cgi->submit('align'),
                );

        if ($user) {
            my $help_url = "Html/help_for_assignments_and_rules.html";
            push ( @$html, $cgi->br, $cgi->br,
                               "<a href=$help_url target=\"help\">Help on Assignments, Rules, and Checkboxes</a>",
                               $cgi->br, $cgi->br,
                               $cgi->submit('assign/annotate'),
                               $cgi->hidden(-name => 'from_sims', -value => 1), "\n"
                   );

            if ($cgi->param('translate')) {
                push( @$html, $cgi->submit('add rules'),
                  $cgi->submit('check rules'),
                  $cgi->br
                  );
            }
        }

        push( @$html, $cgi->br,
                  $cgi->checkbox( -name    => 'checked',
                      -value   => $peg,
                      -override => 1,
                      -checked => 1,
                      -label   => ""
                      )
          );

        my $col_hdrs;
        if ($user && $cgi->param('translate')) {
        push( @$html, " ASSIGN to/Translate from/SELECT current PEG", $cgi->br,
                      "ASSIGN/annotate with form: ", shift @from, $cgi->br,
                          "ASSIGN from/Translate to current PEG: ", shift @from
              );
        $col_hdrs = [ "ASSIGN to<hr>Translate from",
                          "Similar sequence",
                          "E-val",
                  "In Sub",
                          "ASSIGN from<hr>Translate to",
                  "Function",
                  "Organism",
                          "Aliases"
                  ];
        } elsif ($user) {
            push( @$html, " ASSIGN to/SELECT current PEG", $cgi->br,
                              "ASSIGN/annotate with form: ", shift @from, $cgi->br,
                              "ASSIGN from current PEG: ", shift @from
                  );
            $col_hdrs = [ "ASSIGN to<hr>SELECT",
                                  "Similar sequence",
                                  "E-val",
                                  "In Sub",
                                  "ASSIGN from",
                                  "Function",
                                  "Organism",
                                  "Aliases"
                      ];
        } else {
            push(@$html, " SELECT current PEG", $cgi->br );
            $col_hdrs = [ "SELECT",
                      "Similar sequence",
                      "E-val",
                      "In Sub",
                      "Function",
                      "Organism",
                      "Aliases"
                      ];
        }

        my $ncol = @$col_hdrs;
        push( @$html, "<TABLE border cols=$ncol>\n",
                  "\t<Caption><h2>Bidirectional Best Hits</h2></Caption>\n",
                      "\t<TR>\n\t\t<TH>",
                      join( "</TH>\n\t\t<TH>", @$col_hdrs ),
                      "</TH>\n\t</TR>\n"
          );

        #  Add the table data, row-by-row

        my $sim;
        foreach $sim ( @sims ) {
        my($id2,$psc) = @$sim;
        my $cbox = &translatable($fig_or_sprout,$id2) ?
            qq(<input type=checkbox name=checked value="$id2">) : "";
        my $id2_link = &HTML::set_prot_links($cgi,$id2);
        chomp $id2_link;

        my @in_sub  = &peg_to_subsystems($fig_or_sprout,$id2);
        my $in_sub;
        if (@in_sub > 0) {
            $in_sub = @in_sub;
        } else {
            $in_sub = "&nbsp;";
        }

        my $radio   = $user ? shift @from : undef;
        my $func2   = html_enc( scalar &trans_function_of( $fig_or_sprout, $cgi, $id2 ) );
        ## RAE Added color3. This will color function tables that do not match the original
        ## annotation. This makes is a lot easier to see what is different (e.g. caps/spaces, etc)
        my $color3="#FFFFFF";
        unless ($func2 eq $current_func) {$color3="#FFDEAD"}

        #
        # Colorize organisms:
        #
        # my $org     = html_enc( &org_of($fig_or_sprout, $id2 ) );
        my ($org,$oc) = &org_and_color_of($fig_or_sprout, $id2 );
        $org        = html_enc( $org );

        my $aliases = html_enc( join( ", ", &feature_aliasesL($fig_or_sprout,$id2) ) );

        $aliases = &HTML::set_prot_links($cgi,$aliases);

        #  Okay, everything is calculated, let's "print" the row datum-by-datum:

        $func2 = $func2 ? $func2 : "&nbsp;";
        $aliases = $aliases ? $aliases : "&nbsp;";
        push( @$html, "\t<TR>\n",
              #
              #  Colorize check box by Domain
              #
              "\t\t<TD Align=center Bgcolor=$oc>$cbox</TD>\n",
              "\t\t<TD Nowrap>$id2_link</TD>\n",
              "\t\t<TD Nowrap>$psc</TD>\n",
              "\t\t<TD>$in_sub</TD>",
              $user ? "\t\t<TD Align=center>$radio</TD>\n" : (),
              "\t\t<TD Bgcolor=$color3>$func2</TD>\n",
              #
              #  Colorize organism by Domain
              #
              # "\t\t<TD>$org</TD>\n",
              "\t\t<TD Bgcolor=$oc>$org</TD>\n",
              "\t\t<TD>$aliases</TD>\n",
              "\t</TR>\n"
              );
        }
        push( @$html, "</TABLE>\n" );
        push( @$html, $cgi->end_form );
        push( @$html, "</div>");
        # Set up the Show/Hide button.
        my $button = SeedComponents::Framework::get_button($parameters);
        # Assemble it at the front of the other stuff.
        $retVal = join "\n", "$button&nbsp;&nbsp;$title<br /><br />", @$html;
    }
    # Return the result.
    return $retVal;
}

sub get_connections_by_similarity {
    my($fig_or_sprout,$cgi,$all_pegs) = @_;

#    if ($cgi->param('SPROUT'))
#    {
#	return &get_connections_by_similarity_SPROUT($fig_or_sprout,$all_pegs);
#    }
#    else
#    {
	return &get_connections_by_similarity_SEED($fig_or_sprout,$all_pegs);
#    }
}

sub get_connections_by_similarity_SPROUT {
    my($fig_or_sprout,$all_pegs) = @_;
    my(%in,$i,$j,$peg1,$peg2);

    my $conn = {};

    for ($i=0; $i < @$all_pegs; $i++)
    {
	$in{$all_pegs->[$i]} = $i;
    }

    foreach $peg1 (@$all_pegs)
    {
	$i = $in{$peg1};
	foreach $peg2 (map { $_->[0] } bbhs($fig_or_sprout,$peg1,1.0e-10))
	{
	    $j = $in{$peg2};
	    if (defined($i) && defined($j))
	    {
		push(@{$conn->{$i}},$j);
	    }
	}
    }
    return $conn;
}

sub get_connections_by_similarity_SEED {
    my($fig_or_sprout,$all_pegs) = @_;
    my($i,$j,$tmp,$peg,%pos_of);
    my($sim,%conn,$x,$y);
    Trace("Similarity loop 1.") if T(3);
    for ($i=0; ($i < @$all_pegs); $i++) {
        $tmp = &maps_to_id($fig_or_sprout,$all_pegs->[$i]);
        push(@{$pos_of{$tmp}},$i);
        if ($tmp ne $all_pegs->[$i]) {
            push(@{$pos_of{$all_pegs->[$i]}},$i);
        }
    }
    Trace("Similarity loop 2.") if T(3);
    foreach $y (keys(%pos_of)) {
        $x = $pos_of{$y};
        for ($i=0; ($i < @$x); $i++) {
            for ($j=$i+1; ($j < @$x); $j++) {
                push(@{$conn{$x->[$i]}},$x->[$j]);
                push(@{$conn{$x->[$j]}},$x->[$i]);
            }
        }
    }
    Trace("Similarity loop 3.") if T(3);
    my %reverseAllPegs = ();
    my $pegCount = scalar @$all_pegs;
    for (my $i = 0; $i < $pegCount; $i++) {
        $reverseAllPegs{$all_pegs->[$i]} = $i;
    }
    Trace("Calling sims server for $pegCount pegs.") if T(3);
    my @sims = sims($fig_or_sprout,$all_pegs, 500, 1.0e-5, "raw");
    Trace(scalar(@sims) . " values returned.") if T(3);
    foreach $sim (@sims) {
        if (defined($x = $pos_of{$sim->id2})) {
            foreach $y (@$x) {
                push(@{$conn{$reverseAllPegs{$sim->id1}}},$y);
            }
        }
    }
    Trace("Returning connections.") if T(3);
    return \%conn;
}

sub cluster_genes {
    my($fig_or_sprout,$cgi,$all_pegs,$peg) = @_;
    my(%seen,$i,$j,$k,$x,$cluster,$conn,$pegI,$red_set);

    my @color_sets = ();

    $conn = &get_connections_by_similarity($fig_or_sprout,$cgi,$all_pegs);

    for ($i=0; ($i < @$all_pegs); $i++) {
        if ($all_pegs->[$i] eq $peg) { $pegI = $i }
        if (! $seen{$i}) {
            $cluster = [$i];
            $seen{$i} = 1;
            for ($j=0; ($j < @$cluster); $j++) {
                $x = $conn->{$cluster->[$j]};
                foreach $k (@$x) {
                    if (! $seen{$k}) {
                        push(@$cluster,$k);
                        $seen{$k} = 1;
                    }
                }
            }

            if ((@$cluster > 1) || ($cluster->[0] eq $pegI)) {
                push(@color_sets,$cluster);
            }
        }
    }
    for ($i=0; ($i < @color_sets) && (! &in($pegI,$color_sets[$i])); $i++) {}
    $red_set = $color_sets[$i];
    splice(@color_sets,$i,1);
    @color_sets = sort { @$b <=> @$a } @color_sets;
    unshift(@color_sets,$red_set);

    my $color_sets = {};
    for ($i=0; ($i < @color_sets); $i++) {
        foreach $x (@{$color_sets[$i]}) {
            $color_sets->{$all_pegs->[$x]} = $i;
        }
    }
    return $color_sets;
}

sub build_maps {
    my($fig_or_sprout,$pinned_pegs,$all_pegs,$sz_region, $form_action) = @_;
    my($gg,$loc,$contig,$beg,$end,$mid,$min,$max,$genes,$feat,$fid);
    my($contig1,$beg1,$end1,$map,$peg);

    unless (defined($form_action)) {
      $form_action = "frame.cgi";
    }

    my $cgi = new CGI();

    $gg = [];
    foreach $peg (@$pinned_pegs) {
        $loc = &feature_locationS($fig_or_sprout,$peg);
        ($contig,$beg,$end) = &boundaries_of($fig_or_sprout,$loc);
        if ($contig && $beg && $end) {
            $mid = int(($beg + $end) / 2);
            $min = int($mid - ($sz_region / 2));
            $max = int($mid + ($sz_region / 2));
            $genes = [];
            ($feat,undef,undef) = &genes_in_region($fig_or_sprout,$cgi,&genome_of($peg),$contig,$min,$max);
            foreach $fid (@$feat) {
		my $user = $cgi->param('user');
                ($contig1,$beg1,$end1) = &boundaries_of($fig_or_sprout,&feature_locationS($fig_or_sprout,$fid));
                $beg1 = &in_bounds($min,$max,$beg1);
                $end1 = &in_bounds($min,$max,$end1);
                my $aliases = join( ', ', &feature_aliasesL($fig_or_sprout,$fid) );
                my $function = &function_ofS($fig_or_sprout,$fid,$user);
                my ( $uniprot ) = $aliases =~ /(uni\|[^,]+)/;
                my $info = join('<br/>', "<b>PEG:</b> $fid",
                                         "<b>Contig:</b> $contig1",
                                         "<b>Begin:</b> $beg1",
                                         "<b>End:</b> $end1",
                                         $function ? "<b>Function:</b> $function" : (),
                                         $uniprot ? "<b>Uniprot ID:</b> $uniprot" : ()
                               );

                my $sprout = $cgi->param('SPROUT') ? 1 : "";

                my $fmg = "<a href=\&quot;$form_action\?SPROUT=$sprout&compare_region=1\&num_close=".$cgi->param('num_close'). "\&prot=$fid\&user=$user#compared_regions\&quot>show</a>";

		my $shape = "Rectangle";
		if    (($fid !~ /\.bs\./) && ($beg1 < $end1))        { $shape = "rightArrow" }
		elsif (($fid !~ /\.bs\./) && ($beg1 > $end1))        { $shape = "leftArrow" }

                push(@$genes,[&min($beg1,$end1),
                          &max($beg1,$end1),
                          $shape,
                          ($fid !~ /\.bs\./) ? "grey" : 'black',
                          "",
                          $fid,
                          $info, $fmg]);

                if ($fid =~ /peg/) {
                    push(@$all_pegs,$fid);
                }
            }

            #  Sequence title can be replaced by [ title, url, popup_text, menu, popup_title ]
            my $org = org_of( $fig_or_sprout, $peg );
            my $desc = "Genome: $org<br />Contig: $contig";
            $map = [ [ FIG::abbrev( $org ), undef, $desc, undef, 'Contig' ],
                     0,
                     $max+1 - $min,
                     ($beg < $end) ? &decr_coords($genes,$min) : &flip_map($genes,$min,$max)
                   ];
            push(@$gg,$map);
        }
    }
    &GenoGraphics::disambiguate_maps($gg);
    return $gg;
}

sub closest_pegs {
  my ($parameters) = @_;

  # get parameters from parameter hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};
  my $n             = $parameters->{num_close};

  # get cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # initialize some variables
  my($id2,$d,$peg2,$i);

  # what does this do
  my @closest;
  @closest = map { $id2 = $_->id2; ($id2 =~ /^fig\|/) ? $id2 : () } &sims($fig_or_sprout,$peg,&FIG::max(20,$n*4),1.0e-20,"fig",&FIG::max(20,$n*4));

  if (@closest >= ($n-1)) {
    $#closest = $n-2 ;
  }
  my %closest = map { $_ => 1 } @closest;

  # there are dragons flying around...
  # my @pinned_to = grep { ($_ ne $peg) && (! $closest{$_}) } &in_pch_pin_with($fig_or_sprout,$peg);
  my @pinned_to = &in_pch_pin_with($fig_or_sprout,$peg);

  my $g1 = &genome_of($peg);
  @pinned_to = map {$_->[1] } sort { $a->[0] <=> $b->[0] } map { $peg2 = $_; $d = &crude_estimate_of_distance($fig_or_sprout,$g1,&genome_of($peg2)); [$d,$peg2] } @pinned_to;

  if (@closest == ($n-1)) {
    $#closest = ($n - 2) - &FIG::min(scalar @pinned_to,int($n/2));
    for ($i=0; ($i < @pinned_to) && (@closest < ($n-1)); $i++) {
      if (! $closest{$pinned_to[$i]}) {
	$closest{$pinned_to[$i]} = 1;
	push(@closest,$pinned_to[$i]);
      }
    }
  }

  # return the array of closest pegs
  return @closest;
}

sub who {
    my($id) = @_;

    if ($id =~ /^fig\|/)           { return "FIG" }
    if ($id =~ /^gi\|/)            { return "NCBI" }
    if ($id =~ /^^[NXYZA]P_/)      { return "RefSeq" }
    if ($id =~ /^ref\|/)           { return "RefSeq" }
    if ($id =~ /^sp\|/)            { return "SwissProt" }
    if ($id =~ /^uni\|/)           { return "UniProt" }
    if ($id =~ /^tigr\|/)          { return "TIGR" }
    if ($id =~ /^img\|/)           { return "IMG" }
    if ($id =~ /^tigrcmr\|/)       { return "TIGR" }
    if ($id =~ /^pir\|/)           { return "PIR" }
    if ($id =~ /^kegg\|/)          { return "KEGG" }
    if ($id =~ /^tr\|/)            { return "TrEMBL" }
    if ($id =~ /^eric\|/)          { return "ASAP" }
    if ($id =~ /^emb\|/)           { return "EMBL" }
}


sub trans_function_of {
    my ($fig_or_sprout, $cgi, $peg) = @_;

    if (wantarray()) {
        my @funcs = &function_ofL($fig_or_sprout,$peg);
        if ($cgi->param('translate')) {
            @funcs = map { $_->[1] = &translate_function($fig_or_sprout,$_->[1]); $_ } @funcs;
        }
        return @funcs;
    } else {
        my $func = &function_ofS($fig_or_sprout,$peg,scalar $cgi->param('user'));
        if ($cgi->param('translate')) {
            $func = &translate_function($fig_or_sprout,$func);
        }
        return $func;
    }
}


sub in_cluster_with {
  my ($parameters) = @_;

  # get parameters from parameters hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};

  # get cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # initialize in_cluster hash
  my %in_cluster;

  # what does this do?
  if (($FIG_Config::use_pch_server or $fig_or_sprout->table_exists('fc_pegs')) and
      $fig_or_sprout->is_complete(&FIG::genome_of($peg)))
  {
    Trace("Reading cluster map.") if T(3);
    %in_cluster = map { $_->[0] => &get_evidence_link($_->[0],$_->[1]) } $fig_or_sprout->coupled_to($peg);
    Trace(scalar(keys %in_cluster) . " coupling results returned.") if T(3);
    if (keys(%in_cluster) > 0) {
      $in_cluster{$peg} = "";
    } elsif ($cgi->param('fc')) {
      %in_cluster = map { $_ => "" } $fig_or_sprout->in_cluster_with($peg);
      if (keys(%in_cluster) == 1) {
	my @tmp = keys(%in_cluster);
	delete $in_cluster{$tmp[0]};
      }
    }
  }
  Trace("Returning cluster hash.") if T(3);
  # return a reference to the in_cluster hash
  return \%in_cluster;
}

sub get_translation_function {
  my ($parameters) = @_;

  # get parameters from parameters hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id_curr};

  # get cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # get the current user
  my $user = $cgi->param('user');

  # check if the return value is expected to be scalar or array
  if (wantarray()) {
    my $x;
    my @funcs = &function_ofL($fig_or_sprout,$peg, $user);

    if ($cgi->param('translate')) {
      @funcs = map { $x = $_; $x->[1] = &translate_function($fig_or_sprout,$x->[1]); $x } @funcs;
    }
    return @funcs;

  } else {
    my $func = &function_ofS($fig_or_sprout,$peg,$user);
    if ($cgi->param('translate')) {
      $func = &translate_function($fig_or_sprout,$func);
    }

    return $func;
  }
}

sub get_region_data {
  my ($parameters) = @_;

  # get parameters from parameters hash
  my $fig_or_sprout = $parameters->{fig_object};
  my $peg           = $parameters->{peg_id};

  # get cgi object
  my $cgi = $parameters->{cgi} || new CGI();

  # check if the passed id exists
  if (&is_real_feature($fig_or_sprout,$peg)) {

    # determine organism and domain of the PEG
    my $org     = &genome_of($peg);
    my $domain  = &genome_domain($fig_or_sprout,$org);

    # set default minimum size for euk or non-euk display region
    my $half_sz = ($domain =~ m/^euk/i) ? 50000 : 5000;

    # check if the location of the PEG can be retrieved
    if (my $loc = &feature_locationS($fig_or_sprout,$peg)) {

      # get the boundaries
      my($contig,$beg,$end) = &boundaries_of($fig_or_sprout,$loc);

      # perform scaling operations
      my $len  = abs($end-$beg) + 1;
      if ($len > $half_sz) {
        $half_sz = $len;
      }

      my $min  = &max(0,&min($beg,$end) - $half_sz);
      my $max  = &max($beg,$end) + $half_sz;

      # initialize feat and genes variable
      my $feat;

      # retrieve all features to be displayed
      # require Time::HiRes;
      # my $t1 = Time::HiRes::time();
      ($feat,$min,$max) = &genes_in_region($fig_or_sprout,$cgi,&genome_of($peg),$contig,$min,$max);
      # my $t2 = Time::HiRes::time();
      # printf STDERR "Elapse time = %0.4f sec\n", $t2-$t1;

      # return the min and max values as well as a list of features
      return ($min, $max, $feat);

    } else {
      return (-1, "could not get a location for $peg");
    }
  } else {
    return (-1, "$peg is not a real feature");
  }
}

sub sims {
    my( $fig_or_sprout, $peg, $max, $cutoff, $select, $expand, $group_by_genome, $filters ) = @_;
    my( @tmp, $id, $genome, @genomes, %sims, $sim );

    @tmp = $fig_or_sprout->sims( $peg, $max, $cutoff, $select, $expand, $filters );
    # @tmp = grep { !($_->id2 =~ /^fig\|/ } @tmp;
    my $del = $fig_or_sprout->is_deleted_fid_bulk(map { $_->id2 } grep { $_->id2 =~ /^fig\|/} @tmp);
    print STDERR Dumper(DEL => $del);
    # @tmp = grep { !($_->id2 =~ /^fig\|/ and $fig_or_sprout->is_deleted_fid($_->id2)) } @tmp;
    if (! $group_by_genome)  { return @tmp };

    #  Collect all sims from genome with the first occurance of the genome:
    foreach $sim ( @tmp )
    {
        $id = $sim->id2;
        $genome = ($id =~ /^fig\|(\d+\.\d+)\.peg\.\d+/) ? $1 : $id;
        if (! defined( $sims{ $genome } ) ) { push @genomes, $genome }
        push @{ $sims{ $genome } }, $sim;
    }
    return map { @{ $sims{$_} } } @genomes;
}

sub set_ec_and_tc_links {
  my ($fig_or_sprout, $org, $func) = @_;

  # get cgi object
  my $cgi = new CGI();

  if ($func =~ /^(.*)(\d+\.\d+\.\d+\.\d+)(.*)$/) {
    my $before = $1;
    my $ec     = $2;
    my $after  = $3;

    return &set_ec_and_tc_links($fig_or_sprout,$org,$before) . &set_ec_to_maps($fig_or_sprout,$org,$ec,$cgi) . &set_ec_and_tc_links($fig_or_sprout,$org,$after);
  } elsif ($func =~ /^(.*)(TC \d+(\.[0-9A-Z]+){3,6})(.*)$/) {
    my $before = $1;
    my $tc     = $2;
    my $after  = $4;

    return &set_ec_and_tc_links($fig_or_sprout,$org,$before) . &set_tc_link($fig_or_sprout,$org,$tc) . &set_ec_and_tc_links($fig_or_sprout,$org,$after);
  }

  return $func;
}

sub evidence_codes {
    my($fig,$peg) = @_;

    if ($peg !~ /^fig\|\d+\.\d+\.peg\.\d+$/) { return "" }

    my @codes = grep { $_->[1] =~ /^evidence_code/i } $fig->get_attributes($peg);
    my @pretty_codes = ();
    foreach my $code (@codes) {
	my $pretty_code = $code->[2];
	if ($pretty_code =~ /;/) {
	    my ($cd, $ss) = split(";", $code->[2]);
	    $ss =~ s/_/ /g;
	    $pretty_code = $cd;# . " in " . $ss;
	}
	push(@pretty_codes, $pretty_code);
    }
    return @pretty_codes;
}

sub possible_extensions {
  my($fig_or_sprout, $peg,$closest_pegs) = @_;
  my($g,$sim,$id2,$peg1,%poss);

  $g = &genome_of($peg);

  foreach $peg1 (@$closest_pegs) {
    if ($g ne &genome_of($peg1)) {
      foreach $sim (&sims($fig_or_sprout,$peg1,500,1.0e-5,"all")) {
	$id2 = $sim->id2;
	if (($id2 ne $peg) && ($id2 =~ /^fig\|$g\./) && &possibly_truncated($fig_or_sprout,$id2)) {
	  $poss{$id2} = 1;
	}
      }
    }
  }
  return keys(%poss);
}

###
#
# General Functions, should go to a separate module
#
###

sub flip_map {
    my($genes,$min,$max) = @_;
    my($gene);

    foreach $gene (@$genes) {
        ($gene->[0],$gene->[1]) = ($max - $gene->[1],$max - $gene->[0]);
	if      ($gene->[2] eq "rightArrow")  { $gene->[2] = "leftArrow" }
	elsif   ($gene->[2] eq "leftArrow")   { $gene->[2] = "rightArrow" }
    }
    return $genes;
}

sub in_bounds {
    my($min,$max,$x) = @_;

    if     ($x < $min)     { return $min }
    elsif  ($x > $max)     { return $max }
    else                   { return $x   }
}

sub decr_coords {
    my($genes,$min) = @_;
    my($gene);

    foreach $gene (@$genes) {
        $gene->[0] -= $min;
        $gene->[1] -= $min;
    }
    return $genes;
}

sub in {
    my($x,$xL) = @_;
    my($i);

    for ($i=0; ($i < @$xL) && ($x != $xL->[$i]); $i++) {}
    return ($i < @$xL);
}

sub chked_if { $_[0] ? 'checked ' : '' }

sub select_if { $_[0] ? 'selected ' : '' }

sub html_enc { $_ = $_[0]; s/\&/&amp;/g; s/\>/&gt;/g; s/\</&lt;/g; $_ }

sub match_color {
    my ( $b, $e, $n ) = @_;
    my ( $l, $r ) = ( $e > $b ) ? ( $b, $e ) : ( $e, $b );
    my $hue = 5/6 * 0.5*($l+$r)/$n - 1/12;
    my $cov = ( $r - $l + 1 ) / $n;
    my $sat = 1 - 10 * $cov / 9;
    my $br  = 1;
    rgb2html( hsb2rgb( $hue, $sat, $br ) );
}

sub hsb2rgb {
    my ( $h, $s, $br ) = @_;
    $h = 6 * ($h - floor($h));
    if ( $s  > 1 ) { $s  = 1 } elsif ( $s  < 0 ) { $s  = 0 }
    if ( $br > 1 ) { $br = 1 } elsif ( $br < 0 ) { $br = 0 }
    my ( $r, $g, $b ) = ( $h <= 3 ) ? ( ( $h <= 1 ) ? ( 1,      $h,     0      )
                                      : ( $h <= 2 ) ? ( 2 - $h, 1,      0      )
                                      :               ( 0,      1,      $h - 2 )
                                      )
                                    : ( ( $h <= 4 ) ? ( 0,      4 - $h, 1      )
                                      : ( $h <= 5 ) ? ( $h - 4, 0,      1      )
                                      :               ( 1,      0,      6 - $h )
                                      );
    ( ( $r * $s + 1 - $s ) * $br,
      ( $g * $s + 1 - $s ) * $br,
      ( $b * $s + 1 - $s ) * $br
    )
}

sub rgb2html {
    my ( $r, $g, $b ) = @_;
    if ( $r > 1 ) { $r = 1 } elsif ( $r < 0 ) { $r = 0 }
    if ( $g > 1 ) { $g = 1 } elsif ( $g < 0 ) { $g = 0 }
    if ( $b > 1 ) { $b = 1 } elsif ( $b < 0 ) { $b = 0 }
    sprintf("#%02x%02x%02x", int(255.999*$r), int(255.999*$g), int(255.999*$b) )
}

sub floor {
    my $x = $_[0];
    defined( $x ) || return undef;
    ( $x >= 0 ) || ( int($x) == $x ) ? int( $x ) : -1 - int( - $x )
}

sub flat_array {

    my @kv_pairs = @_;
    my @return_args=();
    my @args;

    foreach my $x (@kv_pairs)
    {
        #cannot be a nested array to be passed in to gather

        my @args = ($x->[0], $x->[1]);
        push(@return_args, "$x->[0]\t$x->[1]");
    }

    return @return_args;
}

sub sprout_bbhs_request_form {
        my ($parameters) = @_;

        # get parameters from the parameters hash
        my $peg = $parameters->{peg_id};
        my $form_target = $parameters->{form_target} || "protein.cgi";

        my $cgi = new CGI();
        my $trans_role = $cgi->param('translate');
        my $user = $cgi->param('user');

        my $html = "";

        # create the form
        $html .=  <<"End_Short_Form";

<FORM Action=\"$form_target\">
     <input type=hidden name=prot      value=\"$peg\">
     <input type=hidden name=bbhs      value=1>
     <input type=hidden name=SPROUT    value=1>
     <input type=hidden name=user      value=\"$user\">
     <input type=hidden name=translate value=$trans_role>
     <input type=submit name='Bidirectional Best Hits'
value='Bidirectional Best Hits'>

</FORM>

End_Short_Form

        # return the html string
        return $html;
}
