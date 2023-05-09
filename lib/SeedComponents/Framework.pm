package SeedComponents::Framework;

use WebApplicationComponents qw(tabulator menu list table);
use Data::Dumper;
use FIG_Config;

1;

=head3 get_preferences

    my $prefHash = SeedComponents::Framework::get_preferences($params);

Retrieve the current user's preferences. The preferences are stored in the user directory,
in a file named C<framework.conf>. The single argument is a reference to a hash with
the following elements.

=over 4

=item fig

FIG object used to access the data store.

=item user

Name of the user whose preferences are desired.

=item user_directory

Directory containing the user preferences.

=item RETURN

Returns a hash containing the user's saved preferences. The hash is produced by
executing the contents of the user's preference file.

=back

=cut

sub get_preferences {
  # Get the parameters.
  my ($params) = @_;

  # get variables from params hash
  my $fig  = $params->{fig};
  my $user = $params->{user};
  my $dir  = $params->{user_directory};

  # initialize preferences
  my $preferences = {};

  # open preferences file
  my $filename = $dir . $user . "/framework.conf";
  if (open(FH, $filename)) {
    my $file_content = "";
    while (<FH>) {
      $file_content .= $_;
    }
    close FH;

    # evaluate file content
    eval($file_content);

  } else {
    print STDERR "no preferences file found, possibly new user\n";
  }

  # return the preferences
  return $preferences;
}


sub set_preferences {
  # get params hash
  my ($params) = @_;

  # get variables from params hash
  my $user        = $params->{user};
  my $dir         = $params->{user_directory};
  my $preferences = $params->{preferences};

  # check if user directory exists, otherwise create it
  unless (-d $dir . $user) {
    mkdir $dir . $user or die "Could not create user directory '" . $dir . $user . "'.";
  }

  my $dumper = Data::Dumper->new([$preferences], ['preferences']);

  # overwrite the old preferences with the new ones
  my $filename = $dir . $user . "/framework.conf";
  open(FH, ">$filename") or die "Could not open user preferences file '$filename'.";
  print FH $dumper->Dump();
  close FH;

  # setting preferences was successful, return true
  return 1;
}

=pod

=item * B<get_plain_header> ()

Returns the Header in the plain version

=over 2

=back

=cut

sub get_plain_header {
  my ($parameters) = @_;

  my $motd = get_motd($parameters);

  # create params hash for get_version
  my $params = { fig      => $parameters->{fig_object},
		 fig_disk => $parameters->{fig_disk}
	       };

  # create the html for the plain version title
  my $html .= qq~<table width="100%" cellspacing=2 >
<tr>
<td bgcolor="lightblue">

<b><font size="+3" >The SEED: an Annotation/Analysis Tool Provided by <a href="Html/FIG.html">FIG</a></font></b>
<br>
[ <a href="http://subsys.info">Subsystem Forum</a> |
<a href="~ . $FIG_Config::cgi_base . qq~eggs.cgi">Essentiality Data</a> |
<a href="~ . $FIG_Config::cgi_base . qq~Html/tutorials.html">FIG Tutorials</a> |
<a href="~ . $FIG_Config::cgi_base . qq~p2p/new_seed_update_page.cgi?user=">Peer-to-peer Updates</a> |
<a href="~ . $FIG_Config::cgi_base . qq~p2p/ch.cgi?user=">(New) Clearinghouse</a> |
<a href="~ . $FIG_Config::cgi_base . qq~seed_ctl.cgi?user=">SEED Control Panel</a> |
<a href="http://www.nmpdr.org/">NMPDR</a> |
<a href="http://www-unix.mcs.anl.gov/SEEDWiki/">SEED Wiki</a>]
<br>
[<a href="http://www.genomesonline.org/">GOLD</a> |
<a href="~ . $FIG_Config::cgi_base . qq~Html/CompleteSeedGenomes.html">"Complete" Genomes in SEED </a> |
<a href="http://au.expasy.org/">ExPASy</a> |
<a href="http://img.jgi.doe.gov/">IMG</a> |
<a href="http://www.genome.jp/kegg/kegg2.html">KEGG</a> |
<a href="http://www.ncbi.nlm.nih.gov/">NCBI</a> |
<a href="http://www.tigr.org/tigr-scripts/CMR2/CMRGenomes.spl">TIGR cmr</a> |
<a href="http://www.pir.uniprot.org/">UniProt</a> |
<a href="http://fogbugz.nmpdr.org/">Report "Bugz"</a>]
<br>
<br>
<table width=100%><tr><td><a class="version">~ . get_version($params) . qq~</a></td></tr></table>
</td>
<td >
<img src="./Html/FIGsmall.gif" alt="The SEED" valign="center" align="right">
</td>
</tr>
</table><p>$motd</p>~;

  # return the html string
  return $html;
}

sub get_title {
  # get params hash
  my ($params) = @_;

  # initialize content variable
  my $content = "The SEED";

  # return html
  return $content;
}

sub get_motd {
  # get params hash
  my ($params) = @_;
  my $motd_file = $params->{fig_disk} . "config/motd";
  my $motd = "";

  if (open(F, "<$motd_file")) {
    while (<F>) {
      $motd .= $_;
    }
    close(F);
  }
  return $motd;
}


sub get_logo {
  # get params hash
  my ($params) = @_;

  # initialize content variable
  my $content = "";

  my $motd = get_motd($params);
  # create content
  $content = qq~
<table width=100%>
   <tr>
      <td colspan=3 style="width: 100%; height: 80px; background-color: lightblue; color: black; padding-left: 20px; padding-right: 20px;"><span class="title" style="color: black;">The SEED: </span>
        <span style="color: black; cursor: pointer; font-size: 20pt; font-weight: bold;" id="xxx" onclick="showtip();" class="showme">...</span>
        <span style="color: black; cursor: pointer; font-size: 20pt; font-weight: bold;" id="ooo" onclick="hidetip();" class="hideme">mighty oaks</span>
        <span class="title" style="color: black;"> from little acorns grow</span>
        <span class="title" style="color: black; font-size: 8pt; font-style: italic;">(English proverb)</span>
      </td>
      <td rowspan=2><img src="~ . $params->{image_base} . qq~FIGsmall.gif"></td>
   </tr>
   <tr>
      <td><a class="version">~ . get_version($params) . qq~</a></td><td>$motd</td><td class="version" style="text-align: right;"><a href="Html/seedtips.html#configure" target="help" style="color: red;">Help me configuring this page</a></td>
   </tr>
</table>
~;

  # return html
  return $content;
}

sub get_version {
  my ($params) = @_;

  # get fig object from params hash
  my $fig      = $params->{fig};
  my $fig_disk = $params->{fig_disk};

  # get version from file head
  my @ver = FIG::file_head($fig_disk . "CURRENT_RELEASE", 1);
  my $ver = $ver[0];
  chomp $ver;

  # if this is a cvs version, append time string
  if ($ver =~ /^cvs\.(\d+)$/) {
    ($sec,$min,$hour,$mday,$mon,$year) = localtime($1);
    my $d = "$mon\/$mday\/" . ($year + 1900) . " $hour\:$min\:$sec";
    chomp($d);
    $ver .=  " ($d)";
  }

  # retrive host name
  my $host = FIG::get_local_hostname();

  # return version html string
  return uc($fig->get_system_name()) . " version <b>$ver</b> on $host";
}

sub get_overview {
  my ($params) = @_;

  # get fig object from params hash
  my $fig = $params->{fig};

  # initialize content variable
  my $content = "";

  # get counts from database
  my( $at, $bt, $et, $vt, $envt ) = $fig->genome_counts;
  my( $ac, $bc, $ec ) = $fig->genome_counts("complete");

  # create table containing the values
  $content .= qq~
<p class="headline">Overview of Genome Contents</p>
<table style="border-spacing: 5px;">
   <tr><td colspan=6 style="font-size: 16pt;">Genomes Contained in this instance</td></tr>
   <tr><td></td><td><b>archaeal</b></td><td><b>bacterial</b></td><td><b>eukaryal</b></td><td><b>viral</b></td><td><b>environmental</b></td></tr>
   <tr><td style="padding-right: 5px;"><b>total</b></td><td style="text-align: center;">$at</td><td style="text-align: center;">$bt</td><td style="text-align: center;">$et</td><td style="text-align: center;">$vt</td><td style="text-align: center;">$envt</td></tr>
   <tr><td style="padding-right: 5px;"><b>nearly complete</b></td><td style="text-align: center;">$ac</td><td style="text-align: center;">$bc</td><td style="text-align: center;">$ec</td><td></td></tr>
</table>
~;

  # return content html string
  return $content;
}

sub get_menu {
  # get params hash
  my ($params) = @_;

  # get variables from params hash
  my $user = $params->{user};
  my $action = $params->{action};
  my $cgi = $params->{cgi};

  # initialize content variable
  my $content = "";

  # create content
  my $extlinks = {
		  items => [ "NMPDR", "GOLD", "Complete Genomes in SEED", "NCBI", "KEGG", "ExPASy", "TIGR cmr", "UniProt", "Report Bugz" ],
		  links => [ "http://www.nmpdr.org", "http://www.genomesonline.org/", "./Html/CompleteSeedGenomes.html", "http://www.ncbi.nlm.nih.gov/", "http://www.genome.jp/kegg/kegg2.html", "http://au.expasy.org/", "http://www.tigr.org/tigr-scripts/CMR2/CMRGenomes.spl", "http://www.pir.uniprot.org/", "http://fogbugz.nmpdr.org/" ],
		  title => "External Links",
		  id    => "extlinks"
		 };

  my $intlinks = {
		  items => [ "Subsystem Forum", "FIG Tutorials", "Peer-to-peer Updates", "(New) Clearinghouse", "SEED Control Panel", "SEED Wiki" ],
		  links => [ "http://subsys.info", "./Html/tutorials.html", "./p2p/new_seed_update_page.cgi?user=$user", "./p2p/ch.cgi?user=$user", "./seed_ctl.cgi?user=$user", "http://www-unix.mcs.anl.gov/SEEDWiki/" ],
		  title => "Internal Links",
		  id    => "intlinks"
		 };

  my $config = {
		items => [ "Make this my Start Page", "Revert Changes", "Accept Changes" ],
		links => [ "frame.cgi?set_startpage=1&action=$action&user=$user", "javascript:go_configmode();" ],
		title => "Configuration",
		id    => "config",
		class => "hideme"
	       };

  $content .= menu($intlinks) . menu($extlinks) . menu($config);

  # return html
  return $content;
}

sub get_actionmenu {
  my ($params) = @_;

  my $user = $params->{user};
  my $content = "";

  my $actions = {
		 items => [ "Home", "Curate Subsystems", "Align Sequences", "Candidates for Functional Roles", "Locate PEGs in Subsystems", "Export Assignments", "Process Saved Assignments" ],
		 links => [ "frame.cgi?user=$user", "subsys.cgi?user=$user", "frame.cgi?action=align_sequences&user=$user", "frame.cgi?action=funcrole_candidates&user=$user", "frame.cgi?action=locate_pegs&user=$user", "frame.cgi?action=export_assignments&user=$user", "frame.cgi?action=process_assignments&user=$user" ],
		 title => "Services",
		 id    => "services"
		};

  $content .= menu($actions);

  return $content;
}

sub get_welcome {
  my ($params) = @_;

  # initialize content variable
  my $content = "";

  # get counts from database
  my $fig = $params->{fig};
  my( $at, $bt, $et, $vt, $envt ) = $fig->genome_counts;
  my( $ac, $bc, $ec ) = $fig->genome_counts("complete");

  # create content
  $params->{organism_select_id} = "org_select1";
  $content = qq~<div style="width: 80%; text-align: justify;">
<p class="headline">Welcome to the SEED System</p>

<table style="border-spacing: 5px; top: -15px; left: 50px; position: relative; border: 1px solid lightblue;">
   <tr><td colspan=6 class="table_headline" style="font-weight: bold;">Genomes Contained in this instance</td></tr>
   <tr><td></td><td><b>archaeal</b></td><td><b>bacterial</b></td><td><b>eukaryal</b></td><td><b>viral</b></td><td><b>environmental</b></td></tr>
   <tr><td style="padding-right: 5px;"><b>total</b></td><td style="text-align: center;">$at</td><td style="text-align: center;">$bt</td><td style="text-align: center;">$et</td><td style="text-align: center;">$vt</td><td style="text-align: center;">$envt</td></tr>
   <tr><td style="padding-right: 5px;"><b>nearly complete</b></td><td style="text-align: center;">$ac</td><td style="text-align: center;">$bc</td><td style="text-align: center;">$ec</td><td></td></tr>
</table>

<table width=100%>

<tr><td style="padding-right: 20px; vertical-align: top; text-align: justify;" colspan=2>
<b>Find your gene by searching the text or the sequence data:</b><br/><br/>
Use the text box to search for any alphanumeric identification term, for example 'threonine synthase', 'thrC', 'thrC K12', 'EC 4.2.3.1', 'gi|16127998', 'sp|P00934', 'P00934', 'fig|83333.1.peg.4'.  Multiple terms are joined with AND by default.  Or, use the blast interface to match your DNA or protein sequence to homologs in the database.
</td><td rowspan=2>
<img src="~ . $params->{image_base} . qq~cluster_small.gif" onclick="window.open('~ . $params->{image_base} . qq~cluster.jpg', 'Cluster', 'toolbar=0,location=0,status=0,menubar=0,directories=0,width=801,height=382,scrollbar=0');" style="cursor: pointer;">
</td></tr>

<tr><td style="padding-top: 15px;">~ . get_textsearch($params) . qq~</td><td style="padding-top: 15px;">~ . get_blastsearch($params) . qq~</td></tr>

<tr><td colspan=3><hr/></td></tr>

<tr><td style="padding-right: 20px; vertical-align: top; text-align: justify;" colspan=2>
<b>Explore genomes</b><br/><br/>
First select an individual organism or domain of interest.  To find information such as the genome size in basepairs or proteins, and the annotation status, click the stats button.  To view a metabolic reconstruction, which is a categorized list of proteins responsible for performing vital functions of the cell, click on the subsystems button.
</td><td rowspan=2>
<img src="~ . $params->{image_base} . qq~subsystem_small.gif" onclick="window.open('~ . $params->{image_base} . qq~subsystem.jpg', 'Subsytem', 'toolbar=0,location=0,status=0,menubar=0,directories=0,width=470,height=150,scrollbar=0');" style="cursor: pointer;">
</td></tr>
~;
$params->{organism_select_id} = "org_select2";
$content .= qq~<tr><td colspan=2 style="padding-top: 15px;">~ . get_organisms($params) . qq~</td></tr>

</table>

</div>
~;

  # return html hash
  return $content;
}

sub get_search {
  my ($params) = @_;

  my $content = "";

  $content .= get_textsearch($params) . "<br/>" . get_organisms($params) . "<br/>" . get_subsystems($params);

  return $content;
}

sub get_organisms {
  my ($params) = @_;

  # retrieve fig and cgi objects from params hash
  my $fig = $params->{fig};
  my $cgi = $params->{cgi};
  my $id  = $params->{organism_select_id};

  my @values;
  my $label;
  my $attribute;

  # this is just a hash that will put the bacteria first, then the euks, then the archs, and so on
  my %sort=(
	    "Virus"               => '4',
	    "Eukaryota"           => '3',
	    "Bacteria"            => '1',
	    "Archaea"             => '2',
	    "unknown"             => '5',
	    "Environmental Sample"=> '9',
	   );


  if (exists($params->{sorted_organisms_list})) {
    @values = @{$params->{sorted_organisms_list}->{vals}};
    $label = $params->{sorted_organisms_list}->{labels};
  } else {
    my %domains;
    my @g = $fig->genomes(1);
    map { $domains->{$_} = $fig->genome_domain($_) } @g;

    my @sorted = sort {$sort{$domains{$a}} <=> $sort{$domains{$b}}
			 || uc($fig->genus_species($a)) cmp uc($fig->genus_species($b))} @g;
    foreach my $genome (@sorted) {
      push @values, $genome;
      $label->{$genome}=$fig->genus_species($genome), " ($genome)";
      $attribute->{$genome}={class=>$fig->genome_domain($genome)}; $attribute->{$genome}=~ s/\s+//g;
    }
    $params->{sorted_organism_list} = { labels => $label, vals => \@values };

    unshift(@values, "_choose_org");
    $label->{_choose_org} = "Pick an organism";

    $params->{sorted_organisms_list}->{vals} = \@values;
    $params->{sorted_organisms_list}->{labels} = $label;
  }

  my $content = qq~
<form action="frame.cgi" method="post" name="organism_form">
   <table>
      <tr><td id="organism" class="plain" colspan=2>~ . $cgi->popup_menu(-name       => 'genome',
									 -id         => $id,
									 -style      => "width: 4in",
									 -values     => \@values,
									 -labels     => $label,
									 -attributes => $attribute ) . qq~</td></tr>
      <tr><td><input type="button" value="Metabolic Reconstruction" onclick="submit_organism('~ . $id . qq~', 'metabolism');"></td>
          <td><input type="button" value="Statistics" onclick="submit_organism('~ . $id . qq~', 'statistics');"></td></tr>
   </table>
   ~ . $params->{background_information} . qq~
   <input type="hidden" name="action" value="show_organism">
   <input type="hidden" name="organism_action" value="statistics" id="organism_action">
</form>
~;

  if (defined($params->{simple})) {
    $content = $cgi->popup_menu(-name       => 'genome',
				-id         => $id,
				-style      => "width: 4in",
				-values     => \@values,
				-labels     => $label,
				-attributes => $attribute );
    delete($params->{simple});
  }

  return $content;
}

sub get_subsystems {
  my ($params) = @_;

  # retrieve fig and cgi objects from params hash
  my $fig = $params->{fig};
  my $cgi = $params->{cgi};

  my @values = sort $fig->all_subsystems();

  my %labels;
  foreach my $v (@values) {
    my $l = $v;
    $l =~ s/_/ /g;
    $labels{$v} = $l;
  }

  $labels{_choose_sub} = "Pick a subsystem";
  unshift(@values, "_choose_sub");

  my $content = qq~
<form action="subsys.cgi" method="post">
   <table>
      <tr><td id="subsystem" class="plain">~ . $cgi->popup_menu(-name   => 'ssa_name',
								-style  => "width: 4in",
								-values => \@values,
								-labels => \%labels, ) . qq~</td><td><input type="submit" value="browse Subsystem"></td></tr>
   </table>
   <input type="hidden" name="sort" value="~ . $params->{user_preferences}->{'framework:sort_subsystem'} . qq~">
   <input type="hidden" name="show_clusters" value="~ . $params->{user_preferences}->{'framework:show_clusters_subsystem'} . qq~">
   <input type="hidden" name="request" value="show_ssa">
   ~ . $params->{background_information} . qq~
</form>
~;

  return $content;
}

sub get_textsearch {
  my ($params) = @_;

  my $content = qq~
<form action="index.cgi" method="post">
   <table>
      <tr><td id="textsearch" class="plain"><input type="text" name="pattern" value="Enter search term" style="width: 200px;" onfocus="if (document.getElementById('pattern').value=='Enter search term') { document.getElementById('pattern').value=''; }" id="pattern"></td></tr>
      <tr><td><input type="submit" value="Text Search"></td></tr>
   </table>
   <input type="hidden" name="Search" value="1">
   <input type="hidden" name="fromframe" value="1">
   ~ . $params->{background_information} . qq~
</form>
~;

  return $content;
}

sub get_blastsearch {
  my ($params) = @_;

  $params->{simple} = 1;
  $params->{organism_select_id} = "org_select1";

  my $content = qq~
<form action="frame.cgi" method="post" name="blast_form">
   <table>
      <tr><td id="blastsearch" class="plain"><textarea name="sequence" cols=55 rows=5 id="sequence" onfocus="if (document.getElementById('sequence').value=='paste in Protein or DNA Sequence') { document.getElementById('sequence').value=''; }">paste in Protein or DNA Sequence</textarea></td></tr>
<tr><td colspan=2>~ . get_organisms($params) . qq~</td></tr>
      <tr class="hideme" id="advanced_blast"><td><table><tr><td><select name="blast_tool" id="blast_tool">
<option selected="selected" value="blastp">blastp</option>
<option value="blastx">blastx</option>
<option value="blastn">blastn</option>
<option value="tblastn">tblastn</option>
<option value="Protein scan_for_matches">Protein scan_for_matches</option>
<option value="DNA scan_for_matches">DNA scan_for_matches</option>
</select></td><td>Options <input type="text" name="blast_options"></td></tr>
</table></td></tr>
      <tr><td><table width=100%><tr><td><input type="button" value="Blast Search" onclick="check_sequence('org_select1');"></td><td style="text-align: right;"><input type="button" value="more" onclick="extend('advanced_blast');" id="advanced_blast_button"></td></tr></table></td></tr>
   </table>
   <input type="hidden" name="tool" id="tool" value="blastp">
   <input type="hidden" name="action" value="execute_blast">
   ~ . $params->{background_information} . qq~
</form>
~;

  return $content;
}

sub get_alignsequences {
  my ($params) = @_;

  my $content = qq~<form method="post" action="index.cgi">
<p class="headline">Align Sequences</p>
<input type="hidden" name="user" value="~ . $params->{user} . qq~"><input type="submit" name="Align Sequences" value="Align Sequences">: <input type="text" name="seqids" tabindex="44"  size="100"></form>~;

  return $content;
}

sub get_funcrolecandidates {
  my ($params) = @_;

  my $content = qq~<form method="post" action="index.cgi">
<p class="headline">Search for Candidates for Functional Roles</p>
<table>
<tr><td>Search Pattern</td><td><input type="text" name="pattern" tabindex="3"  size="65" /></td></tr>
<tr><td>Search</td><td><select name=search_kind>
		           <option value=DIRECT  >Directly</option>
		           <option value=GO  >Via Gene Ontology</option>
		           <option value=HUGO  >Via HUGO Gene Nomenclature Committee</option>
	               </select></td></tr>
<tr><td colspan=2>Max Genes: <input type="text" name="maxpeg" tabindex="5" value="100" size="6" />&nbsp; &nbsp; Max Roles: <input type="text" name="maxrole" tabindex="6" value="100" size="6" /><label><input type="checkbox" name="substring_match" value="on" tabindex="7">Allow substring match</label></td></tr>
</table>
<input type="hidden" name="Find Genes in Org that Might Play the Rol" value="Find Genes in Org that Might Play the Role">
<input type="hidden" name="user" value="~ . $params->{user} . qq~">
<input type="submit" value="execute search">
~;

  return $content;
}

sub get_locatepegs {
  my ($params) = @_;

  my $content = qq~
<p class="headline">Locate PEGs in Subsystems</p>
If you wish to locate PEGs in subsystems, you have two approaches supported. You can
 give a FIG id, and you will get a list of all homologs in the designated genome that occur in subsystems.
Alternatively, you can specify a functional role, and all PEGs in the genome that match that role will be shown.
<form method="post" action="index.cgi">
Genome: <input type="text" name="genome" tabindex="46"  size="15" /><br />Search: <input type="text" name="subsearch" tabindex="47"  size="100" /><br /><input type="submit" tabindex="48" name="Find PEGs" value="Find PEGs" />
<input type="hidden" name="user" value="~ . $params->{user} . qq~">
</form>~;

  return $content;
}

sub get_exportassignments {
  my ($params) = @_;

  my $content = qq~
<p class="headline">Export Assignments</p>
<form method=post action=index.cgi>
<table>
	<tr>
		<td>Extract assignments made by </td>
		<td><input type="text" name="made_by" tabindex="30"  size="25" /> (do not prefix with <b>master:</b>)</td>
	</tr>
	<tr>
		<td>Save as user: </td>
		<td><input type="text" name="save_user" tabindex="31"  size="25" /> (do not prefix with <b>master:</b>)</td>
	</tr>
	<tr>
		<td>After date (MM/DD/YYYY) </td>
		<td><input type="text" name="after_date" tabindex="32"  size="15" /></td>
	</tr>
</table>
<label><input type="checkbox" name="tabs" value="1" tabindex="33" />Tab-delimited Spreadsheet</label><br/>
<label><input type="checkbox" name="save_assignments" value="1" tabindex="34" />Save Assignments</label><br/>
<input type="submit" tabindex="35" name="Extract Assignments" value="Extract Assignments">
</form>
~;

  return $content;
}

sub get_processassignments {
  my ($params) = @_;

  my $content = qq~
<p class="headline">Process Saved Assignments</p>
<form method=post action=index.cgi>
You can generate a set of assignments as translations of existing assignments.  To do so, you need to make sure that you fill in the <b>Save as user</b> field just above.  You should use something like <b>RossO</b> (leave out the <b>master:</b>).  When you look at the assignments (and decide which to actually install), they will be made available under that name (but, when you access them, you will normally be using something like <b>master:RossO</b>)<br /><br />
From: <textarea name="from_func" tabindex="36" rows="4" cols="100"></textarea><br /><br />
To:&nbsp;&nbsp;&nbsp;&nbsp; <input type="text" name="to_func" tabindex="37"  size="100" /><br />
<a target="help" href="Html/seedtips.html#replace_names" class="help">Help with generate assignments via translation</a><input type="submit" tabindex="38" name="Generate Assignments via Translation" value="Generate Assignments via Translation" />
</form>
~;

  return $content;
}

sub get_message {
  my ($message) = @_;

  my $content = "<div class='message'>$message</div>";

  return $content;
}

sub get_js_css_links {
  my $html_path = "./Html";

  return qq~<script src="$html_path\/css/FIG.js" type="text/javascript"></script>
	<script type="text/javascript" src="$html_path\/layout.js"></script>
	<link type="text/css" rel="stylesheet" href="$html_path\/frame.css">~;
}

sub get_headline {
  my ($headline) = @_;

  return "<a name='$headline'></a><span class='headline'>" . $headline . "</span>";
}

sub get_body {
  my ($parameters) = @_;

  my $body          = $parameters->{body};
  my $id            = $parameters->{id};
  my $initial_value = $parameters->{initial_value};

  my $initial_class = "hideme";
  if ($initial_value eq "expanded") {
    $initial_class = "showme";
  }

  $body = "<span id='$id\_content' class='$initial_class'>" . $body . "</span>";

  return $body;
}

sub get_button {
  my ($parameters) = @_;

  my $id = $parameters->{id};
  my $caption_show  = $parameters->{caption_show} || "show";
  my $caption_hide  = $parameters->{caption_hide} || "hide";
  my $initial_value = $parameters->{initial_value};

  my $ival = $caption_show;
  if ($initial_value eq "expanded") {
    $ival = $caption_hide;
  }

  my $button = "<input type='button' id='$id\_link' value='$ival' onclick='change_element(\"$id\", \"$caption_show\", \"$caption_hide\");'>";

  return $button;
}
