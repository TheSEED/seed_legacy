#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

#### start #####
use InterfaceRoutines;


use HTML;
use strict;
use CGI;
use FIG_CGI;
use FIG;

my $sproutAvail = eval {
    require SproutFIG;
    require PageBuilder;
};

my($fig_or_sprout, $cgi) = FIG_CGI::init();
if (ref $fig_or_sprout eq 'SFXlate') {
    my $prot = $cgi->param('prot');
    print $cgi->redirect(-uri => "$FIG_Config::cgi_url/wiki/rest.cgi/NmpdrPlugin/SeedViewer?page=Evidence;feature=$prot",
			 -status => 301);
}

my $html = [];

unshift @$html, "<TITLE>The Homologs in  Clusters Page</TITLE>\n";

if (0)
{
    my $VAR1;
    eval(join("",`cat /tmp/homologs_in_clusters_parms`));
    $cgi = $VAR1;
#   print STDERR &Dumper($cgi);
}

if (0)
{
    print $cgi->header;
    my @params = $cgi->param;
    print "<pre>\n";
    foreach $_ (@params)
    {
	print "$_\t:",join(",",$cgi->param($_)),":\n";
    }

    if (0)
    {
	if (open(TMP,">/tmp/homologs_in_clusters_parms"))
	{
	    print TMP &Dumper($cgi);
	    close(TMP);
	}
    }
    exit;
}

my $prot = $cgi->param('prot');
if (! $prot)
{
    push(@$html,"<h1>Sorry, you need to specify a protein</h1>\n");
    &HTML::show_page($cgi,$html);
    exit;
}


if ($prot !~ /^fig\|/)
{
    my @poss = $fig_or_sprout->by_alias($prot);
    if (@poss > 0)
    {
	$prot = $poss[0];
    }
    else
    {
	push(@$html,"<h1>Sorry, $prot appears not to have a FIG id at this point</h1>\n");
	&HTML::show_page($cgi,$html);
	exit;
    }
}

&compute_desired_homologs($fig_or_sprout,$cgi,$html,$prot);

if (ref $fig_or_sprout eq 'SFXlate')
{
    my $h = { homologs => $html,
              title => "NMPDR Homologs in Clusters Page"};

    print "Content-Type: text/html\n";
    print "\n";
    my $templ = "$FIG_Config::template_url/Homologs_tmpl.php";
    print PageBuilder::Build("$templ", $h,"Html");
}
else
{
    &HTML::show_page($cgi,$html);
}
exit;

sub compute_desired_homologs {
    my($fig_or_sprout,$cgi,$html,$peg) = @_;

    my @pinned = &relevant_homologs($fig_or_sprout,$cgi,$peg);
#   print STDERR &Dumper(\@pinned);

#    my @clusters = sort { (@$b <=> @$a) } &sets_of_homologs($fig_or_sprout,$cgi,$peg,\@pinned);
#   print STDERR &Dumper(\@clusters);

#    my @homologs = &extract_homologs($peg,\@pinned,\@clusters);
#   print STDERR &Dumper(\@homologs);

    my $sc;
    my @tab = map { my($peg,$sc,$sim) = @$_; [$sim,$sc,
				       &HTML::fid_link($cgi,$peg),
				       $fig_or_sprout->genus_species($fig_or_sprout->genome_of($peg)),
				       scalar $fig_or_sprout->function_of($peg,scalar $cgi->param('user')),
				       &HTML::set_prot_links($cgi,join( ', ', $fig_or_sprout->feature_aliases($peg) ))
				      ] } @pinned;
    if (@tab > 0)
    {
	push(@$html,&HTML::make_table(["Sim. Sc.","Cluster Size","PEG","Genome", "Function","Aliases"],\@tab,"PEGs that Might Be in Clusters"));
    }
    else
    {
	push(@$html, $cgi->h1("Sorry, we have no clusters containing homologs of $peg"));
    }
}

sub relevant_homologs {
    my($fig_or_sprout,$cgi,$peg) = @_;
    my($maxN,$maxP,$genome1,$sim,$id2,$genome2,%seen);

    $maxN = $cgi->param('maxN');
    $maxN = $maxN ? $maxN : 50;

    $maxP = $cgi->param('maxP');
    $maxP = $maxP ? $maxP : 1.0e-10;

    my @sims = $fig_or_sprout->sims( $peg, $maxN, $maxP, "fig");

    my @homologs = ();
    $seen{&FIG::genome_of($peg)} = 1;
    foreach $sim (@sims)
    {
	$id2     = $sim->id2;
	$genome2 = &FIG::genome_of($id2);
	my @coup;
	if ((! $seen{$genome2}) && (@coup = $fig_or_sprout->coupled_to($id2)) && (@coup > 0))
	{
	    $seen{$genome2} = 1;
	    push(@homologs,[$id2,@coup+1,$sim->psc]);
	}
    }
    return sort { $b->[1] <=> $a->[1] } @homologs;
}

sub sets_of_homologs {
    my($fig_or_sprout,$cgi,$given_peg,$pinned) = @_;
    my($peg,$mid,$min,$max,$feat,$fid);

    my $bound = $cgi->param('bound');
    $bound = $bound ? $bound : 4000;

    my @pegs = ();
    foreach $peg (($given_peg,@$pinned))
    {
	my $loc = $fig_or_sprout->feature_location($peg);
	if ($loc)
	{
        my($contig,$beg,$end) = $fig_or_sprout->boundaries_of($loc);
	    if ($contig && $beg && $end)
	    {
		$mid = int(($beg + $end) / 2);
		$min = $mid - $bound;
		$max = $mid + $bound;

		($feat,undef,undef) = &genes_in_region($fig_or_sprout,$cgi,&FIG::genome_of($peg),$contig,$min,$max);
		foreach $fid (@$feat)
		{
		    if (&FIG::ftype($fid) eq "peg")
		    {
			push(@pegs,$fid);
		    }
		}
	    }
	}
    }

    my %represents;
    foreach $peg (@pegs)
    {
	my $tmp = $fig_or_sprout->maps_to_id($peg);
	push(@{$represents{$tmp}},$peg);
#	if ($tmp ne $peg) { push(@{$represents{$peg}},$peg) }
    }
    my($sim,%conn,$x,$y,$i,$j);
    foreach $y (keys(%represents))
    {
	$x = $represents{$y};
	for ($i=0; ($i < @$x); $i++)
	{
	    for ($j=$i+1; ($j < @$x); $j++)
	    {
		push(@{$conn{$x->[$i]}},$x->[$j]);
		push(@{$conn{$x->[$j]}},$x->[$i]);
	    }
	}
    }

    my $maxN = $cgi->param('maxN');
    $maxN = $maxN ? $maxN : 50;

    my $maxP = $cgi->param('maxP');
    $maxP = $maxP ? $maxP : 1.0e-10;

    foreach $peg (@pegs)
    {
	foreach $sim ($fig_or_sprout->sims( $peg, $maxN, $maxP, "raw"))
	{
	    if (defined($x = $represents{$sim->id2}))
	    {
		foreach $y (@$x)
		{
		    push(@{$conn{$peg}},$y);
		}
	    }
	}
    }

    my(%seen,$k,$cluster);
    my @clusters = ();
    for ($i=0; ($i < @pegs); $i++)
    {
	$peg = $pegs[$i];
	if (! $seen{$peg})
	{
	    $cluster = [$peg];
	    $seen{$peg} = 1;
	    for ($j=0; ($j < @$cluster); $j++)
	    {
		$x = $conn{$cluster->[$j]};
		foreach $k (@$x)
		{
		    if (! $seen{$k})
		    {
			push(@$cluster,$k);
			$seen{$k} = 1;
		    }
		}
	    }

	    if (@$cluster > 1)
	    {
		push(@clusters,$cluster);
	    }
	}
    }
    return @clusters;
}

sub extract_homologs {
    my($given_peg,$pinned,$clusters) = @_;
    my(%main,$cluster,$peg,%counts,@with_counts);

    %main = map { $_ => 1 } ($given_peg,@$pinned);
    foreach $cluster (@$clusters)
    {
	foreach $peg (@$cluster)
	{
	    if (! $main{$peg})
	    {
		$counts{&FIG::genome_of($peg)} += @$cluster - 1;
	    }
	}
    }

    foreach $peg (($given_peg,@$pinned))
    {
	push(@with_counts,[$peg,$counts{&FIG::genome_of($peg)}]);
    }

    return grep { $_->[1] > 2} sort { $b->[1] <=> $a->[1] } @with_counts;
}
