#
# Copyright (c) 2003-20012 University of Chicago and Fellowship
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

use FIG;
my $fig = new FIG;

use HTML;
use strict;
use GenoGraphics;
use CGI;
my $cgi = new CGI;
use FIG_CGI;
use SeedComponents;

my ($fig, $cgi, $user) = FIG_CGI::init(debug_save   => 0,
				       debug_load   => 0,
				       print_params => 0
				      );

my $html = [];
push( @$html, "<link type='text/css' rel='stylesheet' href='./Html/frame.css'>" );

my $feature = $cgi->param( 'feature' );
if ( $feature && $feature !~ /^fig\|/ )
{
    $feature = $_  if ( $_ = $fig->by_alias( $feature ) )
}

if ( ! $feature )
{
    unshift @$html, "<TITLE>The SEED Feature Page</TITLE>\n";
    push(@$html,"<h1>Sorry, you need to specify a feature</h1>\n");
}
elsif ( $feature =~ /^fig\|/ )
{
    my $request = $cgi->param("request") || "";

    if    ($request eq "view_annotations")       { &view_annotations($fig,$cgi,$html,$feature); }
    elsif ($request eq "view_all_annotations")   { &view_all_annotations($fig,$cgi,$html,$feature); }
    elsif ($request eq "dna_sequence")           { &dna_sequence($fig,$cgi,$html,$feature); }
    else                                         { &show_initial($fig,$cgi,$html,$feature); }
}
else
{
    unshift @$html, "<TITLE>The SEED Feature Page</TITLE>\n";
    push(@$html,"<h1>Sorry, $feature appears not to have a FIG id at this point</h1>\n");
}

&HTML::show_page($cgi,$html);


#==============================================================================
#  view_annotations
#==============================================================================

sub view_annotations {
    my($fig,$cgi,$html,$feature) = @_;

    unshift @$html, "<TITLE>The SEED:Feature Annotations</TITLE>\n";
    my $col_hdrs = ["who","when","annotation"];
    my $tab = [ map { [$_->[2],$_->[1],"<pre>" . $_->[3] . "<\/pre>"] } $fig->feature_annotations($feature) ];
    if (@$tab > 0)
    {
	push(@$html,&HTML::make_table($col_hdrs,$tab,"Annotations for $feature"));
    }
    else
    {
	push(@$html,"<h1>No Annotations for $feature</h1>\n");
    }
}


sub view_all_annotations {
    my($fig,$cgi,$html,$peg) = @_;
    my($ann);

    unshift @$html, "<TITLE>The SEED: Feature Annotations</TITLE>\n";
    if ($fig->is_real_feature($peg))
    {
	my $col_hdrs = ["who","when","PEG","genome","annotation"];
	my @related  = $fig->related_by_func_sim($peg,$cgi->param('user'));
	push(@related,$peg);

	my @annotations = $fig->merged_related_annotations(\@related);

	my $tab = [ map { $ann = $_;
			  [$ann->[2],$ann->[1],&HTML::fid_link($cgi,$ann->[0]),
			   $fig->genus_species(&FIG::genome_of($ann->[0])),
			   "<pre>" . $ann->[3] . "</pre>"
			   ] } @annotations];
	if (@$tab > 0)
	{
	    push(@$html,&HTML::make_table($col_hdrs,$tab,"All Related Annotations for $peg"));
	}
	else
	{
	    push(@$html,"<h1>No Annotations for $peg</h1>\n");
	}
    }
}


#==============================================================================
#  show_initial
#==============================================================================

sub show_initial {
    my($fig,$cgi,$html,$feature) = @_;

    unshift @$html, "<TITLE>The SEED: Feature Page</TITLE>\n";
    my $gs = $fig->org_of($feature);

    if (! $fig->is_real_feature($feature))
    {
	push(@$html,"<h1>Sorry, $feature is an unknown identifier</h1>\n");
    }
    else
    {
	push(@$html,"<h1>Feature $feature: $gs</h1>\n");
	&display_fid($fig,$cgi,$html,$feature);
    }
}

#==============================================================================
#  display_fid
#==============================================================================

sub display_fid {
    my($fig,$cgi,$html,$fid) = @_;
    my $loc;

    my $graph = &SeedComponents::Protein::get_peg_view({ fig_object => $fig,
									  peg_id     => $fid
									  }
									);
    push(@$html,$graph);
    
    my $contextH = &SeedComponents::Protein::get_chromosome_context({ fig_object => $fig,
										       peg_id     => $fid
										       }
										     );

    push(@$html,$contextH->{table});

    push @$html, $cgi->hr;
    my $query = $cgi->url(-query => 1);
    $query =~ s/^[^?]*\?//;
    my $link1 = "$FIG_Config::cgi_url/feature.cgi?$query&request=view_annotations";
    my $link2 = "$FIG_Config::cgi_url/feature.cgi?$query&request=view_all_annotations";
    push(@$html,"<br><a href=$link1>To View Annotations</a> / <a href=$link2>To View All Related Annotations</a>\n");


    my $link = "$FIG_Config::cgi_url/feature.cgi?$query&request=dna_sequence";
    push(@$html,"<br><a href=$link>DNA Sequence</a>\n");

    my $user = $cgi->param('user') || '';
    if ( $user )
    {
	$link = "$FIG_Config::cgi_url/fid_checked.cgi?fid=$feature&user=$user&checked=$feature&assign/annotate=assign/annotate";
	push(@$html,"<br><a href=$link target=_blank>To Make an Annotation</a>\n");
    }

    my $has_translation = $fig->translatable($fid);


}

#==============================================================================
#  dna_sequence
#==============================================================================

sub dna_sequence {
    my($fig,$cgi,$html,$fid) = @_;
    my($seq,$func,$i);

    unshift @$html, "<TITLE>The SEED: Nucleotide Sequence</TITLE>\n";
    if ($seq = $fig->dna_seq($fig->genome_of($fid),scalar $fig->feature_location($fid)))
    {
	$func = $fig->function_of($feature,$cgi->param('user'));

	push(@$html,$cgi->pre,">$fid $func\n");
	for ($i=0; ($i < length($seq)); $i += 60)
	{
	    if ($i > (length($seq) - 60))
	    {
		push(@$html,substr($seq,$i) . "\n");
	    }
	    else
	    {
		push(@$html,substr($seq,$i,60) . "\n");
	    }
	}
	push(@$html,$cgi->end_pre);
    }
    else
    {
	push(@$html,$cgi->h1("No DNA sequence available for $fid"));
    }
}


