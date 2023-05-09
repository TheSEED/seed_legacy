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

package InterfaceRoutines;
use Carp;

require Exporter;
@ISA = (Exporter);
@EXPORT = qw(
     abbrev
     add_annotation
     add_attribute
     assign_function
     bbhs
     boundaries_of
     by_alias
     cgi_url
     change_attribute
     coupling_evidence
     coupled_to
     coupling_and_evidence
     crude_estimate_of_distance
     delete_attribute
     dna_seq
     ec_name
     ec_to_maps
     families_for_protein
     family_function
     sz_family
     feature_aliasesL
     feature_aliasesS
     feature_annotations
     feature_attributes
     feature_locationS
     ftype
     function_ofL
     function_ofS
     genes_in_region
     genome_domain
     genome_of
     genus_species
     get_attributes
     key_info
     get_translation
     in_cluster_with
     in_family
     in_pch_pin_with
     is_complete
     is_real_feature
     map_name
     mapped_prot_ids
     maps_to_id
     max
     merged_related_annotations
     min
     neighborhood_of_role
     org_and_color_of
     org_of
     peg_in_gendb
     peg_links
     peg_to_subsystems
     possibly_truncated
     related_by_func_sim
     roles_of_function
     sort_fids_by_taxonomy
     subsystem_curator
     subsystems_for_peg
     sz_family
     table_exists
     to_alias
     translatable
     translate_function
     translation_length
);

use Tracer;

sub add_annotation {
    my($fig_or_sprout,$cgi,$prot,$user,$annotation) = @_;
    Trace("Adding annotation.") if T(Bruce => 4);
    if ((! $cgi->param('SPROUT')) || ($annotation !~ /Set function/))
    {
        Trace("Calling annotation adder.") if T(Bruce => 4);
        $fig_or_sprout->add_annotation($prot,$user,$annotation);
    }
}

sub assign_function {
    my($fig_or_sprout,$prot,$who,$function) = @_;

    $fig_or_sprout->assign_function($prot,$who,$function,"");
}

sub bbhs {
    my($fig_or_sprout,$peg,$cutoff) = @_;

    return $fig_or_sprout->bbhs($peg,$cutoff);
}

sub boundaries_of {
    my($fig_or_sprout,$loc) = @_;

    return $fig_or_sprout->boundaries_of($loc);
}


sub by_alias {
    my($fig_or_sprout,$prot) = @_;
    return $fig_or_sprout->by_alias($prot);
}

sub cgi_url {
    my($fig_or_sprout) = @_;

    return $fig_or_sprout->cgi_url();
}

sub coupled_to {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->coupled_to($peg);
}

sub coupling_evidence {
    my($fig_or_sprout,$peg1,$peg2) = @_;

    return $fig_or_sprout->coupling_evidence($peg1,$peg2);
}

sub coupling_and_evidence {
    my($fig_or_sprout,$peg,$bound,$sim_cutoff,$coupling_cutoff,$try_old) = @_;

    my $keep = $FIG_Config::readonly ? undef : "keep";

    #
    # 2006-1010 - don't try to compute coupling locally. Depend on the precomputed coupling.
    #
    $try_old = undef;

    return $fig_or_sprout->coupling_and_evidence($peg,$bound,$sim_cutoff,$coupling_cutoff,$keep,$try_old);
}

sub crude_estimate_of_distance {
    my($fig_or_sprout,$genome1,$genome2) = @_;

    return $fig_or_sprout->crude_estimate_of_distance($genome1,$genome2);
}

sub dna_seq {
    my($fig_or_sprout,$genome,$loc) = @_;

    return $fig_or_sprout->dna_seq($genome,$loc);
}

sub ec_to_maps {
    my($fig_or_sprout,$ec) = @_;

    return $fig_or_sprout->ec_to_maps($ec);
}

sub ec_name {
    my($fig_or_sprout,$ec) = @_;

    return $fig_or_sprout->ec_name($ec);
}

sub feature_aliasesL {
    my($fig_or_sprout,$fid) = @_;

    my @tmp = $fig_or_sprout->feature_aliases($fid);
    return @tmp;
}

sub feature_aliasesS {
    my($fig_or_sprout,$fid) = @_;

    return scalar $fig_or_sprout->feature_aliases($fid);
}

sub feature_annotations {
    my($fig_or_sprout,$cgi,$prot) = @_;
    if ($cgi->param('SPROUT'))
    {
        return $fig_or_sprout->feature_annotations($prot);
    }
    return $fig_or_sprout->feature_annotations($prot);
}

sub feature_attributes {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->feature_attributes($peg);
}

sub feature_locationS {
    my($fig_or_sprout,$peg) = @_;

    return scalar $fig_or_sprout->feature_location($peg);
}

sub function_ofL {
    my($fig_or_sprout,$peg) = @_;

    my @tmp = $fig_or_sprout->function_of($peg);
    return @tmp;
}

sub function_ofS {
    my($fig_or_sprout,$peg,$user) = @_;

    return scalar $fig_or_sprout->function_of($peg,$user);
}

sub genes_in_region {
    my($fig_or_sprout,$cgi,$genome,$contig,$min,$max) = @_;

    if ($cgi->param('SPROUT'))
    {
        my($x,$feature_id);
        my($feat,$min,$max) = $fig_or_sprout->genes_in_region($genome,$contig,$min,$max);
        my @tmp =  sort { ($a->[1] cmp $b->[1]) or
                              (($a->[2]+$a->[3]) <=> ($b->[2]+$b->[3]))
                        }
                        map  { $feature_id = $_;
                               $x = &feature_locationS($fig_or_sprout,$feature_id);
                               $x ? [$feature_id,&boundaries_of($fig_or_sprout,$x)] : ()
                        }
                        @$feat;
        return ([map { $_->[0] } @tmp],$min,$max);
    }
    else
    {
        return $fig_or_sprout->genes_in_region($genome,$contig,$min,$max);
    }
}

sub genome_domain {
    my($fig_or_sprout,$org) = @_;

    return $fig_or_sprout->genome_domain($org);
}

sub genus_species {
    my($fig_or_sprout,$genome) = @_;

    return $fig_or_sprout->genus_species($genome);
}

sub get_translation {
    my($fig_or_sprout,$prot) = @_;

    return $fig_or_sprout->get_translation($prot);
}

sub in_pch_pin_with {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->in_pch_pin_with($peg);
}

sub in_family {
    my($fig_or_sprout,$id) = @_;

    return $fig_or_sprout->in_family($id);
}

sub is_complete {
    my($fig_or_sprout,$genome) = @_;

    return $fig_or_sprout->is_complete($genome);
}

sub is_real_feature {
    my($fig_or_sprout,$prot) = @_;

    return $fig_or_sprout->is_real_feature($prot);
}

sub map_name {
    my($fig_or_sprout,$map) = @_;

    return $fig_or_sprout->map_name($map);
}

sub mapped_prot_ids {
    my($fig_or_sprout,$cgi,$peg) = @_;

    if (0) # ($cgi->param('SPROUT'))
    {
        return map { [$_,0] } grep { $_ =~ /^(([NXYZA]P_[0-9\.]+)|(tigr\|[0-9a-zA-Z]+)|(gi\|\d+)|(kegg\|\S+)|(uni\|[A-Z0-9]{6})|(sp\|[A-Z0-9]{6}))$/ } &feature_aliasesL($fig_or_sprout,$peg);
    }
    else
    {
        return $fig_or_sprout->mapped_prot_ids($peg);
    }
}

sub maps_to_id {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->maps_to_id($peg);
}

sub merged_related_annotations {
    my($fig_or_sprout,$related) = @_;

    return $fig_or_sprout->merged_related_annotations($related);
}

sub neighborhood_of_role {
    my($fig_or_sprout,$role) = @_;

    return $fig_or_sprout->neighborhood_of_role($role);
}

sub org_and_color_of {
    my($fig_or_sprout,$id) = @_;

    return $fig_or_sprout->org_and_color_of($id);
}

sub org_of {
    my($fig_or_sprout,$prot) = @_;

    return $fig_or_sprout->org_of($prot);
}

sub peg_in_gendb {
    my($fig_or_sprout,$cgi,$peg) = @_;

    if ($cgi->param('SPROUT'))  { return 0 }
    return $fig_or_sprout->peg_in_gendb($peg);
}

sub peg_links {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->peg_links($peg);
}

sub peg_to_subsystems {
    my($fig_or_sprout,$id) = @_;

    return $fig_or_sprout->peg_to_subsystems($id);
}

sub possibly_truncated {
    my($fig_or_sprout,$id) = @_;

    return $fig_or_sprout->possibly_truncated($id);
}

sub related_by_func_sim {
    my($fig_or_sprout,$cgi,$peg,$user) = @_;

    if ($cgi->param('SPROUT'))
    {
        return map { $_->[0] } sort { $a->[1] <=> $b->[1] } $fig_or_sprout->bbhs($peg, 1.0e-10, 0);
    }
    return $fig_or_sprout->related_by_func_sim($peg,$user);
}

sub sort_fids_by_taxonomy {
    my($fig_or_sprout,@fids) = @_;

    return $fig_or_sprout->sort_fids_by_taxonomy(@fids);
}

sub subsystem_curator {
    my($fig_or_sprout,$sub) = @_;

    my $curr =  $fig_or_sprout->subsystem_curator($sub);
    $curr =~ s/^master://;
    return $curr;
}

sub subsystems_for_peg {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->subsystems_for_peg($peg);
}

sub sz_family {
    my($fig_or_sprout,$family) = @_;

    return $fig_or_sprout->sz_family($family);
}

sub table_exists {
    my($fig_or_sprout,$table) = @_;

    return $fig_or_sprout->table_exists($table);
}

sub to_alias {
    my($fig_or_sprout,$peg,$type) = @_;

    return $fig_or_sprout->to_alias($peg,$type);
}

sub translatable {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->translatable($peg);
}

sub translate_function {
    my($fig_or_sprout,$func) = @_;

    return $fig_or_sprout->translate_function($func);
}

sub translation_length {
    my($fig_or_sprout,$peg) = @_;

    return $fig_or_sprout->translation_length($peg);
}


###########################################################

sub abbrev {
    my($genome_name) = @_;

    return &FIG::abbrev($genome_name);
}

sub add_attribute {
    my $fig_or_sprout=shift;

    return $fig_or_sprout->add_attribute(@_);
}

sub change_attribute {
    my $fig_or_sprout=shift;

    return $fig_or_sprout->change_attribute(@_);
}

sub delete_attribute {
    my $fig_or_sprout=shift;

    return $fig_or_sprout->delete_attribute(@_);
}

sub ftype {
    my($feature_id) = @_;

    if ($feature_id =~ /^fig\|\d+\.\d+\.([^\.]+)/) {
        return $1;
    }
    return undef;
}

sub genome_of {
    my $prot_id = (@_ == 1) ? $_[0] : $_[1];

    if ($prot_id =~ /^fig\|(\d+\.\d+)/) { return $1; }
    return undef;
}

sub get_attributes {
    my($fig_or_sprout, $prot) = @_;

    return $fig_or_sprout->get_attributes($prot);
}

sub key_info {
    my($fig_or_sprout, @extra) = @_;

    return $fig_or_sprout->key_info(@extra);
}

sub max {
    my(@x) = @_;
    my($max,$i);

    (@x > 0) || return undef;
    $max = $x[0];
    for ($i=1; ($i < @x); $i++) {
        $max = ($max < $x[$i]) ? $x[$i] : $max;
    }
    return $max;
}

sub min {
    my(@x) = @_;
    my($min,$i);

    (@x > 0) || return undef;
    $min = $x[0];
    for ($i=1; ($i < @x); $i++) {
        $min = ($min > $x[$i]) ? $x[$i] : $min;
    }
    return $min;
}


sub roles_of_function {
    my $func = (@_ == 1) ? $_[0] : $_[1];

    return (split(/\s*[\/;]\s+/,$func),($func =~ /\d+\.\d+\.\d+\.\d+/g));
}

sub families_for_protein {
 my($fig_or_sprout, $prot) = @_;
 return $fig_or_sprout->families_for_protein($prot);
}

sub  family_function {
  my($fig_or_sprout, $prot) = @_;
  return $fig_or_sprout->family_function($prot);
}

sub sz_family {
 my($fig_or_sprout, $prot) = @_;
 return $fig_or_sprout->sz_family($prot);
}
   

1;
