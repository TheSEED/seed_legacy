# -*- perl -*-
#
# Copyright (c) 2003-2013 University of Chicago and Fellowship
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

use warnings;
#  Is there a good reason for calling the subtroutine "main"?
#  Something else is defining it elsewhere. Possibly only in FASTCGI.
no warnings qw(redefine);
use strict;

use CGI qw(:standard);
use HTML::Template;
use Data::Dumper;

use FIG;
use FIG_Config;
use FIG_CGI;
use UserData;
use SeedComponents;
use PageBuilder;
use TemplateObject;
use Tracer;

eval {
    # initialize fig object
    my ($fig, $cgi, $user) = FIG_CGI::init(debug_save   => 0,
                                           debug_load   => 0,
                                           print_params => 0);
    my $nmpdr = (FIGRules::nmpdr_mode($cgi) ? 1 : 0);
    if ($nmpdr && "$FIG_Config::linkinSV") {
        my ($prot) = $cgi->param('prot');
        print  $cgi->redirect(-status => 301, -uri => "$FIG_Config::linkinSV?page=Annotation;feature=$prot");
    } else {
        # Normal user, so do the page.
        print $cgi->header();
        &main($fig, $cgi, $user);
    }
};

warn $@ if $@;
if($@) {
    print start_html();
    print STDERR "EXCEPTION: $@\n";
    print "EXCEPTION: $@\n",end_html();
}

1;


sub main {
    my ($fig, $cgi, $user) = @_;
    Trace("Starting protein page.") if T(2);
    # check if an external page is to be displayed, called with data from seed.
    if ($cgi->param('tool')) {
        Trace("Tool selected.") if T(2);
        # Get the template object.
        my $to = TemplateObject->new($cgi, php => 'Tool');

        # Get the PEG.
        my $pegID = $cgi->param('prot') || '';   # undef is unfriendly

        my $parameters = { fig_object  => $fig,
                           peg_id      => $pegID,
                           table_style => 'plain',
                           fig_disk    => $FIG_Config::fig_disk . "/",
                           form_target => 'protein.cgi',
                           title       => "$pegID Protein Tool Page",
                           user        => ($cgi->param('user') || ""),
        };

        # Format the header information.
        $to->titles($parameters);
        # Spit out an index link.
        $to->add(undef => "<br/>" . SeedComponents::Protein::get_index_link() . "<br/><hr/>");

        # Call the tool.
        $to->add(results => & SeedComponents::Basic::call_tool($fig, $pegID));
                 
        # Spit out another copy of the index link.
        $to->add(undef => "<hr/>" . SeedComponents::Protein::get_index_link());

        # Output the page.
        print $to->finish();

    # check for the new framework
    } elsif ($cgi->param('new_framework')) {
        Trace("Using new framework.") if T(2);
        # display the new version
        my @out = `./frame.cgi`;
        print @out;
        return;
        
    } else {
        
        # display the old version
        
        # Get the template object.
        my $to = TemplateObject->new($cgi, php => 'Protein', scalar $cgi->param("request"));

        # Get the PEG.
        my $pegID = $cgi->param('prot') || '';   # undef is unfriendly
	if ($pegID !~ /^fig\|/) {
	    my @poss = $fig->by_alias($pegID);
	    
	    if (@poss > 0) {
		$pegID = $poss[0];
	    }
	}
        # Get the feature type.
        my $featureType = $fig->ftype($pegID) || 'Undefined Type';  # ndef is unfriendly
        my $proteinMode = ($featureType eq 'peg');
        if ($featureType eq 'peg') {
            $featureType = 'Protein';
        } elsif ($featureType eq 'bs') {
            $featureType = 'RiboSwitch';
        } else {
            $featureType = uc $featureType;
        }
        # Make sure the template knows.
        if ($to->mode()) {
            $to->add(ftype => $featureType);
            $to->add(protein => $proteinMode);
            Trace("Feature $pegID will be displayed as type $featureType with protein mode = $proteinMode.") if T(2);
        }
        # Built the parameter list for the framework stuff.
        my $parameters = { fig_object  => $fig,
                           peg_id      => $pegID,
                           table_style => 'plain',
                           fig_disk    => $FIG_Config::fig_disk . "/",
                           form_target => 'protein.cgi',
                           ftype       => $featureType,
			   cgi         => $cgi,
                           user        => $cgi->param('user') || "",
                           title       => "$featureType Page for $pegID"
        };

	# check if the fig_id passed is valid
        Trace("Checking ID $pegID.") if T(3);
	unless ($fig->translatable($pegID)) {
	    $to->titles($parameters);
	    $to->add("<br/>" . SeedComponents::Protein::get_index_link() . "<br/>") if $to->raw;
	    $to->add(SeedComponents::Framework::get_js_css_links()) if $to->raw;
	    $to->add("<h2>The Protein with ID $pegID does not (no longer) exist.</h2>") if $to->raw;
	    $to->add("<br/>" . SeedComponents::Protein::get_index_link() . "<br/>") if $to->raw;
	    print $to->finish();
	    return 1;
	}

        my ($min, $max, $features) = SeedComponents::Protein::get_region_data($parameters);
        $parameters->{min} = $min;
        $parameters->{max} = $max;
        $parameters->{features} = $features;
        
        # Format the header information.
        $to->titles($parameters);
        # Delete the title.
        delete $parameters->{title};
        # Spit out an index link.
        $to->add("<br/>" . SeedComponents::Protein::get_index_link() . "<br/>") if $to->raw;
        $to->add(SeedComponents::Framework::get_js_css_links()) if $to->raw;

        # check for request parameter
        my $request = $cgi->param("request") || "";

        # check for quick assign. Quick assigns do not work in Sprout, but if we're in Sprout and a
        # fast assign is requested, we've already crashed when we tried to create the template.
        if ($request eq "fast_assign")            {
            &SeedComponents::Protein::make_assignment($fig,$cgi,$pegID);
	    $cgi->delete("request");
	    $parameters->{cgi} = $cgi;
            $request = "";
        }
        Trace("Request value is $request.") if T(3);
        if      ($request eq "view_annotations") {
            $to->add(results => &SeedComponents::Protein::view_annotations($fig,$cgi,$pegID));
        } elsif ($request eq "view_all_annotations") {
            $to->add(results => &SeedComponents::Protein::view_all_annotations($fig,$cgi,$pegID));
        } elsif ($request eq "show_coupling_evidence") { 
            $to->add(results => &SeedComponents::Protein::show_coupling_evidence($fig,$cgi,$pegID));
        } elsif ($request eq "abstract_coupling") {
            $to->add(results => &SeedComponents::Protein::show_abstract_coupling_evidence($fig,$cgi,$pegID));
        } elsif ($request eq "ec_to_maps") {
            $to->add(results => &SeedComponents::Protein::show_ec_to_maps($fig,$cgi));
        } elsif ($request eq "link_to_map") {
            $to->add(results => &SeedComponents::Protein::link_to_map($fig,$cgi));
        } elsif ($request eq "fusions") {
            $to->add(results => &SeedComponents::Protein::show_fusions($fig,$cgi,$pegID));
        } else {
	        # Support calls to previous or next peg.  This version uses locations,
	        # not the previous ad hoc method of simply altering the id.
	        if ( $cgi->param('previous PEG') ) {
                Trace("Processing previous_feature.") if T(3);
	            $cgi->delete('previous PEG');
	            my $pegID2 = $fig->previous_feature( { fid => $pegID, type => 'peg' } );
	            if ( $pegID2 ) {
	                $pegID = $pegID2;
	                $parameters->{peg_id} = $pegID;
	                $cgi->param( -name => 'prot', -value => $pegID, -override => 1 );
	            }
            } elsif ( $cgi->param('next PEG') ) {
                Trace("Processing next_feature.") if T(3);
	            $cgi->delete('next PEG');
	            my $pegID2 = $fig->next_feature( { fid => $pegID, type => 'peg' } );
	            if ( $pegID2 ) {
	                $pegID = $pegID2;
	                $parameters->{peg_id} = $pegID;
	                $cgi->param( -name => 'prot', -value => $pegID, -override => 1 );
	            }
	        }

	    # initialize the return value variable
	    my $retval;

            # normal page shown.
            Trace("Displaying normal page.") if T(3);
	    $retval = SeedComponents::Protein::get_title($parameters);
            $to->add("<br />") if $to->raw;
            $to->add(title => $retval->{body});
            $to->add("<br/><br/>") if $to->raw;
            $to->add(assign => SeedComponents::Protein::get_current_assignment($parameters));
            $to->add("<hr/>") if $to->raw;
            $to->add(translink => SeedComponents::Protein::get_translation_link());
            $to->add("<hr/>") if $to->raw;
            $to->add(context_graphic => SeedComponents::Protein::get_peg_view($parameters));
	    $parameters->{initial_value} = 'expanded';
            Trace("Formatting context.") if T(3);
	    $retval = SeedComponents::Protein::get_chromosome_context($parameters);
	    delete($parameters->{title});
	    delete($parameters->{id});
            $to->add(context_table => "<br/><br/>".$retval->{title} . "<br/><br/>" . $retval->{body});
            $to->add("<br />") if $to->raw;
            Trace("Retrieving annotation links.") if T(3);
	    $to->add(annotation_links => SeedComponents::Protein::get_annotation_links($parameters));
            $to->add("<hr/>") if $to->raw;
            if ($proteinMode) {
                Trace("Processing subsystem connections.") if T(3);
                $parameters->{initial_value} = 'expanded';
                $retval = SeedComponents::Protein::get_subsystem_connections($parameters);
                delete($parameters->{title});
                delete($parameters->{id});
                $to->add(subsys_connections => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
                Trace("Subsystem connections plotted.") if T(3);
            }
            if ($proteinMode) {
                Trace("Processing AA sequence.") if T(3);
                $parameters->{initial_value} = 'collapsed';
                $retval = SeedComponents::Protein::get_aa_sequence($parameters);
                delete($parameters->{title});
                delete($parameters->{id});
                $to->add(protein_sequence => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
                Trace("AA sequence plotted.") if T(3);
            }
            Trace("Generating DNA data.") if T(3);
            $parameters->{initial_value} = 'collapsed';
	    $retval = SeedComponents::Protein::get_dna_sequence($parameters);
	    delete($parameters->{title});
	    delete($parameters->{id});
            $to->add(dna_sequence => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
            $parameters->{initial_value} = 'collapsed';
	    $retval = SeedComponents::Protein::get_dna_sequence_adjacent($parameters);
            delete($parameters->{title});
            delete($parameters->{id});
            $to->add(flanked_sequence => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
            if ($proteinMode) {
                $parameters->{initial_value} = 'expanded';
                $retval = SeedComponents::Protein::get_assignments_for_identical_proteins($parameters);
                delete($parameters->{title});
                delete($parameters->{id});
                $to->add(related_assignments => "<br/><br/>". $retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
            }
            if ($proteinMode) {
                $parameters->{initial_value} = 'collapsed';
                $retval = SeedComponents::Protein::get_links($parameters);
                delete($parameters->{title});
                delete($parameters->{id});
                $to->add(subsys_links => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
            }
            if ($proteinMode) {
                $parameters->{initial_value} = 'collapsed';
                $retval = SeedComponents::Protein::get_functional_coupling($parameters);
                delete($parameters->{title});
                delete($parameters->{id});
                $to->add(couplings => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
            }
            Trace("Processing attribute data.") if T(3);
            $parameters->{initial_value} = 'collapsed';
	    $retval = SeedComponents::Protein::get_attributes($parameters);
	    delete($parameters->{title});
	    delete($parameters->{id});
            $to->add(attributes => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
            if ($proteinMode) {
                $parameters->{initial_value} = 'collapsed';
                $retval = SeedComponents::Protein::get_protein_families($parameters);
                delete($parameters->{title});
                delete($parameters->{id});
                $to->add(families => "<br/><br/>".$retval->{button} . "&nbsp;&nbsp;" . $retval->{title} . "<br/><br/>" . $retval->{body});
            }
            $to->add("<br/><hr/>") if $to->raw;
            $to->add(compared_regions => SeedComponents::Protein::get_compared_regions($parameters));
            $to->add("<hr/>") if $to->raw;
            $to->add(pubmed_url => SeedComponents::Protein::get_pubmed_url($parameters));
            $to->add("<br/><hr/>") if $to->raw;
            if (is_sprout($cgi)) {
                $retval = SeedComponents::Protein::get_bbhs($parameters);
                $to->add(bbhs => $retval);
                delete($parameters->{title});
                delete($parameters->{id});
            }
            $parameters->{initial_value} = 'expanded';
            $retval = SeedComponents::Protein::get_similarities($parameters);
            delete($parameters->{title});
            delete($parameters->{id});
            $to->add(similarities => $retval->{title} . "<br/><br/>" . $retval->{form} . "<br/>" . $retval->{body});
            if ($proteinMode) {
                $to->add("<br/><hr/>") if $to->raw;
                $parameters->{initial_value} = 'expanded';
                $retval = SeedComponents::Protein::get_tools($parameters);
                delete($parameters->{title});
                delete($parameters->{id});
                $to->add(tools => $retval->{body});
            }
            $parameters->{noheadline} = undef;
        }

        $to->add("<br/><hr/>" . SeedComponents::Protein::get_index_link()) if $to->raw;
        
        print $to->finish();
    }
}
