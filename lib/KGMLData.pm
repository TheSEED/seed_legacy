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

###KGMLData Perl Module###
#
# A Object that stores and provides functions for computational analysis
# of KEGG KGML Data that is returned by the PerlSAX parser using KGML.pm
#
# Authors: Kevin Formsma, John Gould, Jeffrey Ambrose
# Contact: kevin.formsma@hope.edu
# Hope College, Summer Research 2005 REU
##########################


package KGMLData;

use strict;

use XML::Parser::PerlSAX;
use KGML;
use FIG;
use Subsystem;

my $fig = new FIG;

###KGMLData Constructor###
# 
# Usage: my $kgml = new KGMLData;
#
##########################
sub new {
my $type = shift;
my $self = {};
    return bless $self, $type;
}


###read_file###
#
# Input: KGMLData object, KEGG xml filepath, a bool
#
# Output: if bool is true, print statments
#
# Parses the KEGG xml file and stored the data in the KGMLData object
###############
sub read_file()
{ 
	my ($self, $filename, $bool) = @_;
	if($bool){
	print "\nReading $filename";
	}
	my $parser = XML::Parser::PerlSAX->new(Handler => (KGML->new()));
	
	$parser->parse( Source => {SystemId => $filename} );	

	my %data_set = (KGML->return_data);	
	$self->{'data'} = ();
	$self->{'data'} = \%data_set;
	if($bool) {
	print "\nFinished parsing the ";
	print "$self->{'data'}->{'pathway'}{'title'} pathway.";
	}
}

sub read_map()
{
    my ($self, $mapid) = @_;
    $self->read_file("$FIG_Config::kgml_dir/map/map$mapid.xml", 0);
}

###get_xml_files_in_dir###
#
# Input: KGMLData object, a directory path
#
# Output: An array of the full path of every .xml file in the specified directory
##########################
sub get_xml_files_in_dir()
{
	my ($self,$dir) = @_;
	my @xmlfiles;
	
	opendir(BIN, $dir) or die "Can't open $dir: $!";
	while( defined (my $file = readdir BIN) ) {
		if($file =~ /\.xml$/)
		{
   	  		push(@xmlfiles,$dir.$file) if -T "$dir/$file";
   	  	}
	}
	closedir(BIN);
	return @xmlfiles;
}

###this code is out of date, but it is used by the Reaction Analysis#####
###best_matching_pathway###
#
# Input: KGMLData object, a directory path of xml files, a list of subsystem ec numbers
#
# Output: Filename of best matching pathway, a array of the matching ec's, a array of all
#   	  matching pathways, each index storing the name and a KEGG link in a subarray.
###########################
sub best_matching_pathway()
{
	my ($self,$dir,@ecs) = @_;
	my ($most_matches,$best_pathway,@match);
	my (@match_pathways);
	$most_matches = 0;
	#iterate through each xml file and find the one with the most matches.
	my @xml_files = KGMLData->get_xml_files_in_dir($dir);
	#print "\nFinding matches in $dir directory.";
	foreach my $file (@xml_files){
		$self->read_file($file,0);	
		my $matchresults = $self->search_for_ecs(@ecs)->{'match'};
		if(@$matchresults)
		{
			my $temp_link = $self->get_pathway_link();
			foreach my $ec (@$matchresults){
				$temp_link = $temp_link."+".substr($ec,3);
			}
			my @temp_array = ($self->current_pathway_title(),$temp_link);
			push(@match_pathways,\@temp_array);
		}
		#print "\nThis many $test Found!!\n";
		if( (scalar @$matchresults) > $most_matches)
		{	
			$most_matches = (scalar @$matchresults);
			$best_pathway = $file;
			@match = @$matchresults;
		}	
	}
	#reread the bestpathway file so we have all of its data in the KGMLData object.
	$self->read_file($best_pathway,0) if defined $best_pathway;	
	return ($best_pathway,$most_matches,\@match,\@match_pathways);

}

###get_matching_pathways###
#
# Input: KGMLData Object, Directory path of xml files, Array of ec's to match for in the pathway
#
# Output: A array, each index containing another array of pathway title, a link, how many matches in it, and filepath.
# This has replaced best_matching_pathway. Use this for new code
###########################
sub get_matching_pathways
{
	my($self,$dir,$ecs,$rnIDs) = @_;
	my %results;
	my @xml_files = $self->get_xml_files_in_dir($dir);
	foreach my $file (@xml_files){
		$self->read_file($file,0);
		my $matchresults = $self->search_for_ecs(@$ecs)->{'match'};
		
		if(scalar @$matchresults>0){
			my $link = $self->get_pathway_link();
			my $count = 0;
			foreach my $ec (@$matchresults){
				$link = $link."+".substr($ec,3);
				$count++;
			}
			
			
			my $linkrns = $self->get_pathway_link();
			$linkrns =~ s/map/rn/;
			foreach my $rn (@$rnIDs){
				$linkrns = $linkrns."+".$rn;
			}
			
			
			my @temp = ($self->current_pathway_number(),
				    $self->current_pathway_title(),$link,$linkrns,$count,$file);
			if(!defined $results{int $count}){
				$results{int $count} = ();
			}
			push(@{$results{int $count}},\@temp);
		}
	}
	my @retVal;
	foreach my $count (reverse sort {$a <=> $b} keys %results){
		push(@retVal,@{$results{$count}})
	}
	return \@retVal;
}



###ec_relation_analysis###
#
# Input: KGMLData Object, Subsystem Object, pathway filepath
#
# Output: Array of matching subsystem ID's and links, A array of the computed linking paths, 
#         and a array of enzymes to possibly add
##########################
sub ec_relation_analysis
{
	my($self,$ec_list) = @_;
	
	my(@matching_id_results,@linking_list,@possible_add);
	
	my @ecs = @{$ec_list};
	if(@ecs){
		my $match = $self->search_for_ecs(@ecs)->{'match'};
		my @matching_ids = $self->ecs_to_ids(@$match);
		my (%relations,%seen,@test_possible_ids);
		foreach my $match_id (@matching_ids){
			#create the hashmap of relations
			my $has = $self->get_relation($match_id);
			$relations{$match_id} = $has;
			#add the id to the seen list for filtering later on
			$seen{$match_id}=1;
			#Create KEGG links and output data to html
			my $ec = $self->id_to_ec($match_id);
			my $temp_link = $self->get_entry_link($match_id);
			push(@matching_id_results,"<a href=\"$temp_link\">".$match_id.",  $ec </a>");
			#Go searching in the pathway tree for missing links
			my $result_ar = $self->search_for_id($match_id,\@matching_ids,0,6,());		
			if(@$result_ar)	{
				foreach my $result_ar_b (@$result_ar){
					push(@linking_list,$result_ar_b);				
				}
			}
		}
		my @possible_ids;
		#filter out duplicates and ids we already have in the subsystem
		foreach my $ref_array (@linking_list){
			foreach my $id (@$ref_array){
				push(@possible_ids,$id) unless $seen{$id}++;	
			}
		}
		#create links for the missing ID's
		my $pathway_missing_link = $self->get_pathway_link();
		foreach my $id (@possible_ids){
			my $ec = $self->id_to_ec($id);
			my $temp_link = $self->get_entry_link($id);
			$pathway_missing_link = $pathway_missing_link."+".substr($ec,3);
			push(@possible_add,"<a href=\"$temp_link\">ID-$id,$ec</a>");
		}
		push(@possible_add,"<a href=\"$pathway_missing_link\">See Missing in Pathway</a>");
		return (\@matching_id_results,\@linking_list,\@possible_add);
	}
}
###show_ec_relation_analysis###
#
# Input: KGMLData Object, Subsystem Object, Pathway filepath, CGI object, HTML data array
#
# Output: HTML formating displaying the results from the function ec_relation_analysis
###############################
sub show_ec_relation_analysis
{
	my($self,$subsystem,$pathway,$cgi,$html) = @_;
	my @ecs = $self->roles_to_ec($subsystem->get_roles());
	$self->read_file($pathway,0);
	my($match_id,$linking_list,$to_add) = $self->ec_relation_analysis(\@ecs);
	my $ssa  = $cgi->param('ssa_name');
	#print welcome header
	push(@$html,$cgi->h3("KEGG Pathway Enzyme Relation"),"Subsystem: $ssa",$cgi->br);
	#print matching ids
	push(@$html,$cgi->br,"Matching ID's in subsystem:");
	foreach my $entry (@$match_id){
		push(@$html,$cgi->br,$entry);
	}
	#print linking lists
	push(@$html,$cgi->br,$cgi->br,"Enzyme linking detected from pathway:") if @$linking_list;
	push(@$html,$cgi->br,"No enzyme linking detected in pathway") unless @$linking_list;
	foreach my $link (@$linking_list){
		push(@$html,$cgi->br,"Link:");
		foreach my $id (@$link){
			push(@$html,"$id"," -- ");
		}
		pop @$html;
	}
	if ((scalar @$to_add) >1) {
	push(@$html,$cgi->br,$cgi->br,"From analysis, consider these enzymes to possibly add to this subsystem:");
	foreach my $entry (@$to_add){
		push(@$html,$cgi->br,$entry);
	}
	}
	
}

###show_matching_pathways###
#
# Input: KGMLData Object, Subsystem Object, CGI objectm HTML data array
#
# Output: HTML formating displaying the results of the functin get_matching_pathways
############################
sub show_matching_pathways
{	
	my($self,$subsystem,$cgi,$html,$hope_reactions) = @_;
	my $ssa  = $cgi->param('ssa_name');
	#get the subsystem EC numbers
	my @ecs = $self->roles_to_ec($subsystem->get_roles());
	my @rns;

	if (defined $hope_reactions)
	{
	    my %hope_rns = %{$hope_reactions};
	    foreach my $role (keys %hope_rns)
	    {
		push @rns, @{$hope_rns{$role}};
	    }
	}
	
	#if defined, lets continue, else print error
	if(@ecs)
	{
		#get a list of the pathways with matches, their links, and how many EC's matched.
		my $matching_array;
		eval {$matching_array = $self->get_matching_pathways($FIG_Config::kgml_dir."/map/",\@ecs,\@rns)};
		if($@ || !defined $matching_array)
		{
			push(@$html, "No Results Found or Error: $@");
		}
		else{
			foreach my $entry (@$matching_array){
#				my($match_id,$linking_list,$to_add) = $self->ec_relation_analysis($subsystem,$entry->[4]);
				push(@$html,"$entry->[1] => ","<a href=\"$entry->[2]\">EC numbers in map $entry->[0]</a> and <a href=\"$entry->[3]\">Hope Reactions in map $entry->[0]</a>  Count=$entry->[4]",$cgi->br,$cgi->br);					
		}
		}		
	}
	else
	{
		push(@$html,"No EC numbers or Hope Reactions in subsystem.");
	}

}



###get_pathway_ecs###
#
# Input: KGMLData Object
#
# Output: hash containing all the ec's we have seen as keys. 
#####################
sub get_pathway_ecs
{
	my ($self) = @_;
	my %seen;
	my $entrys = $self->{'data'}->{'entry'};
	foreach my $entry (keys %$entrys ) {
		if(!defined $entrys->{$entry}->{"map"}) {
			my $ec = $self->id_to_ec($entry);		
			$seen{$ec} = 0 if $ec =~ /ec:/;
		}
	}
	return \%seen;
}

###form_links###
#
# Input: KGMLData Object, a array of ec numbers to appened
#
# Output: weblink of the pathway in kegg with the EC numbers highlighted
################
sub form_links
{
	my ($self,$data_ar) = @_;
	my $link_found = $self->get_pathway_link();	
	foreach my $ec (@$data_ar){
		$link_found = $link_found."+".substr($ec,3);
	}
	return ($link_found);
}

###all_subsystem_roles###
#
# Input: KGMLData Object, an array of subsystem names
#
# Output: a hash, with keys as subsystem names, values as a array of the ec numbers
# 		  in that subsystem.
#########################
sub all_subsystem_roles
{
	my($self,@ssn) = @_;
	my %result;
	foreach my $name (@ssn){
		$result{$name} = $self->subsystem_roles($name);
	}
	return \%result;
}

###subsystem_roles###
#
# Input: KGMLData Object, subsystem name
#
# Output: An array of all the EC's in that subsystem
#####################
sub subsystem_roles
{
	my ($self,$name) = @_;
	my $subsystem = Subsystem->new($name,$fig,0);
	my @ecs = $self->roles_to_ec($subsystem->get_roles());
	return \@ecs;
}

###pathway_coverage###
#
# Input: KGMLData Object, hash of keys as subsystem names, and values as arrays of ecs
#
# Output: An array of arrays, with (subsystem name, KEGG weblink)
# This tells us about what ec's in the pathway are currently in a subsystem in SEED
######################
sub pathway_coverage
{
	my ($self,$ss_hash_r) = @_;
	my @results;
	my @found;
	foreach my $entry (keys %$ss_hash_r){	
		my $array = $ss_hash_r->{$entry};
		my $result = $self->search_for_ecs(@$array)->{'match'};
		push(@found,@$result);
		#Here we have the data in pathway_ecs_hr. Just need links
		my ($link_found) = $self->form_links($result);
		my @temp = ($entry,$link_found);
		push(@results,\@temp) if $link_found =~ /\+\d+\.\d+\.\d+\.\d+/;
	}
	my $templink = $self->get_pathway_link();
	my %seen;
	foreach my $ec (@found){
		$seen{$ec}++;
	}
	foreach my $ec ( keys %{$self->get_pathway_ecs()}) {
		$templink = $templink."+".substr($ec,3) unless $seen{$ec};	
	}
	my @temp = ('Show Missing',$templink);
	push(@results,\@temp);
	return \@results;
}

###pathway_coverage_all###
#
# Input: KGMLData Object, path of the xml file directory, hash of keys as subsystem names, and values as arrays of ecs
#
# Output: the results of the pathway coverage analysis, an array of arrays of arrays. 
##########################
sub pathway_coverage_all
{
	my ($self,$dir,$ss_hash_r) = @_;
	my @results;
	my @dir = $self->get_xml_files_in_dir($dir);
	foreach my $path (@dir){
		$self->read_file($path,0);
		my $temp = $self->pathway_coverage($ss_hash_r);
		my @array = ($self->current_pathway_title(),$temp);
		undef $temp;
		push(@results,\@array);
	}
	return \@results;
}

###get_relation###
#
# Input: KGMLData Object, ID element from xml data
#
# Output: all the ID's that the query ID is related to in a array
##################
sub get_relation
{
	my ($self, $query) = @_;
	my (@to,@from);
	my $relation_list_ref = $self->{'data'}->{'relation'};			   
	foreach my $hash (@$relation_list_ref)
	{
		#print "\nRelation: $hash->{'entry1'} to $hash->{'entry2'}";
		
	}
	foreach my $relation_hash_ref (@$relation_list_ref){
		my %rel_att = %$relation_hash_ref;
		#this is a TO relation
		
		if($rel_att{'entry1'} == $query){
			push(@to,$rel_att{'entry2'});		
		}
		#this is a FROM relation
		if($rel_att{'entry2'} == $query){
			#push(@from, $rel_att{'entry1'});
		}	
	}
	return \@to;
}

###search_for_id###
#
# This is a recursive function used to travel the enzyme relation trees. 
# It returns enzyme linking lists. Matching against $match_list (array), and the current_id is your original query
# when you start.
###################
sub search_for_id
{
	my ($self,$current_id,$match_list_ar,$current_depth,$cutoff,$seen) = @_;
	#print "\nSearching with current id: $current_id Depth: $current_depth";
	my $next_to_ar = get_relation($self,$current_id);
	if($cutoff == $current_depth) {
		#print "\nReached Cutoff, returning";
		return undef;		
	}
	foreach my $match (@$match_list_ar){
		if($match eq $current_id && $current_depth > 0){
		#this needs to return a list of lists per say
			my @temp = ($current_id);
			my @return = (\@temp);
			#print "Found match to $match";
			return \@return;
		}
	}
	my @list_of_result_lists;
	if(scalar @$next_to_ar == 0){
		#print "\nNo relations found.";
		return undef;
	}	
	else {
		my @id_relations;
		#print "\nFiltering results";  NOTE this fitlering was undesirable, commented out. 
		foreach my $element (@$next_to_ar) {
			push(@id_relations,$element); #unless $seen->{$element}++;
		}
		
		foreach my $relation (@id_relations) {			
			my $result_ar = search_for_id($self,$relation,$match_list_ar,$current_depth+1,$cutoff,$seen);
			#here we need to append data			
			if(@$result_ar)
			{
				#print "\nIn this case for $current_id:";
				foreach my $lists (@$result_ar){
					my @temp = ($current_id);
					push (@temp, @$lists);
				    #print "\tFound one match @temp\n";
					push (@list_of_result_lists, \@temp);
				}
			}			
		}
		#return \@list_of_result_lists;
	}
	return \@list_of_result_lists;
}








#search_for_ecs takes in a array of ec numbers, and searches for matches
#in the data from the objects XML parsing. It stores both missing and matches.
#It returns a reference to a hashmap, with keys 'match', and 'missing', which
# return references to arrays of the matching and missing ec's.
sub search_for_ecs()
{
	my ($self, @eclist) = @_;
	
	my @matched;
	my @missing;
	my %seen;
	$seen{""} = 1;
	my $entry_set = $self->{'data'}{'entry'};
	#loop through each entry element, checking for ec number matches

	foreach my $key (keys %$entry_set)
	{			
		foreach my $ec (@eclist)
		{
			#some names have the ec number, then orth data behind it, this takes just the first ec number
			#for accurate matching
			my @temp = split(/\ /,$entry_set->{$key}->{'name'});
			if($temp[0] eq $ec)
			{
				#print "\nI Matched here! $ec";
				push(@matched,$ec) unless $seen{$ec}++;
			}
			elsif($entry_set->{$key}->{'type'} eq 'enzyme')
			{				
				push(@missing,$entry_set->{$key}->{'name'});
			}
		}
	}	
	return {'match' => \@matched,'missing' => \@missing};	
}

###ecs_to_ids###
#
# Input: KGMLData Object, Array of ecs to convert
#
# Output: an array of ids
################
sub ecs_to_ids()
{
	my ($self,@ecs) = @_;
	my @results;
	foreach my $ec (@ecs) {
		push(@results,$self->ec_to_id($ec));
	}
	return @results;
}

#finds the id number of a given ec within the pathway
sub ec_to_id()
{
	my($self,$ec) = @_;
	my $id;
	my $entry_set_ref = $self->{'data'}{'entry'};
	my %entry_set = %$entry_set_ref;
	#loop through each entry element, checking for ec number matches
	foreach my $key (keys %entry_set)
	{
		my $entry = $entry_set{$key};
		my @temp = split(/\ /,$entry->{'name'});		
			if($temp[0] eq $ec)
			{
				#print "\nI Matched here! $ec";
				$id = $key;
			}
	}
	return $id;	
};
#returns the ec number of a given ID
sub id_to_ec()
{
	my($self,$id) = @_;
	my @temp = split(/\ /,$self->{'data'}->{'entry'}->{$id}->{'name'});
	return $temp[0];
}

#returns the ec numbers in XML format found in the roles
sub roles_to_ec()
{
	my ($self, @roles) = @_;
	my @result;
	my %seen = ("" => 1);
	foreach my $temp (@roles) {
	    #remove everything but the ec number;	
	    
	    if($temp =~ /\d+\.\d+\.\d+\.\d+/){
		#add the 'ec:' to the beginning so that it matches the xml format for ec #s
		$temp = "ec:".$&;
		#print "\n$temp";
		push(@result,$temp) unless $seen{$temp}++;
	    }	
	}
	return @result;
}

sub current_pathway_title
{
	my ($self) = @_;
	return $self->{'data'}->{'pathway'}->{'title'};
}

sub current_pathway_number
{
	my ($self) = @_;
	return $self->{'data'}->{'pathway'}->{'number'};
}

sub get_entry_link
{
	my ($self,$id) = @_;
	return $self->{'data'}->{'entry'}->{$id}->{'link'};
}

sub get_pathway_link
{
	my ($self) = @_;
	return $self->{'data'}->{'pathway'}->{'link'};
}



# METHOD get_reaction_products
# finds reactions given with compound ID
#
# takes( reaction name(KEGGID) )
#
# returns( array containing the product IDs )
sub get_reaction_products
{
    my($self, $reaction) = @_;
    
    #get the array containing the product id's
    return $self->{'data'} ->{'reaction'}-> {$reaction} -> {'product'} ;

    
    
}




# METHOD get_compound_substrate
# Gets the reactions which involove this compound as a substrate
#
# takes ( compound )
#
# returns (reaction)
sub get_compound_substrate
{
    my( $self, $compound) = @_;
    my ( @reactions, $reaction );

    #get  the reaction data
    $reaction = $self->{'data'} -> {'reaction'};
    
    #iterate throguh and get all of the reaction data for this compund
    foreach (keys %$reaction)
    {
    	foreach my $hash (@{$reaction -> {$_} -> {'substrate'}}){
	    
	    if($hash eq $compound)
	    {
		push (@reactions, $reaction -> {$_} -> {'name'});
	    }
	}
    }

    return \@reactions;
    
}
# METHOD find_links_between
# finds reactions between two given compounds
#
# takes( starting compound, ending compound )
#
# returns( String containing the substrate ID )
sub find_links_between
{
    my ($self,$html, $startComp, $endComp, $thisPath, $allPaths, $usedCompounds) = @_;
    my (@reactions, $products);

    #get the reactions that this compound is involved with
    @reactions = @{$self->get_compound_substrate($startComp)};

#    push(@$html,"SEARCHING...<BR>") if (!defined $thisPath);

    #iterate through each of the reactions
    foreach my $thisReaction (@reactions)
    {

	#create a new array for this reaction
	my @currentPath;
	
	#add the reaction to this path
	if (!defined $thisPath)
	{
	    $thisPath = \@currentPath;
#	    push(@$html,"DEFININNG THISPATH...<br>");
	}
	
	else
	{
	    push (@currentPath, @{$thisPath});
	}

	push (@currentPath, $thisReaction);
	
	#check to see if we are at the end compound
	$products = $self->get_reaction_products($thisReaction);
	
#	push(@$html,"Products:");

	#iterate through the arry of compound names
	foreach(@{$products})
	{
#	    push(@$html,"$_");

	    if(index($usedCompounds, "$_") < 0)
	    {
		$usedCompounds .= "$_";
		if("$_" eq $endComp)
		{
		    #we are done finding a path, add it to the completed array
#		    push(@$html,"<b>We found a path!</b><br>");
		    push(@{$allPaths}, \@currentPath);
		}
		
		#otherwise, preform the same check on the current reaction
		else
		{
#		    push(@$html,"DID NOT FIND PATH, RESEARCHING...<br>");
		    $allPaths = $self->find_links_between($html,$_, $endComp, \@currentPath, $allPaths, $usedCompounds) if (@currentPath <15);
		}
	    }
	}
    }

    return $allPaths;

}

# METHOD find_many_links
# takes an array of starting compounds and an array of ending compounds and finds all
# of the possible reactions between every possible combination
#
# takes (array of starting compounds, array of ending compounds)
#
# returns (Hash of reactions with keys of begging compounds, pointing to a hash of keys of ending compounds
#           which point to the array of all possible reactions)
sub find_many_links
{
    my ($self, $start, $end, $html) = @_;
    my (@startComp, @endComp, $currentStart, $currentEnd, $reactionCombinations);
	
    #construct the arrays containg the inputs.
    @startComp = @{$start};
    @endComp = @{$end};

    #iterate through every start compound
    foreach $currentStart (@startComp)
    {

	#remove the spaces
	$currentStart =~ s/ //g;    
	
	
	#create a new hash for this combination
	my %thisCompare;
	
	#iterate through every ending compound for each start
	foreach $currentEnd (@endComp)
	{
	    #remove the spaces
	    $currentEnd =~ s/ //g;    


	    #map the current combination to the array containg all of the possible reactions
	    $thisCompare{$currentEnd} = $self -> find_links_between($html, $currentStart, $currentEnd);
	}

	#map the start compound to this hash
	$reactionCombinations -> {$currentStart} = \%thisCompare;
  
    }

    return $reactionCombinations;
}


# METHOD associate_enzymes
# gets the enzymes associated with a set of reactions
#
# takes( array of reactions)
#
# returns ( an hash with reactions as keys pointing to an array containing  enzymes required )
sub associate_enzymes
{
    my ($self, $html, $reactions) = @_;
    my ($results, $entry);

    #iterate through all of the reactions
    foreach my $thisReaction (@{$reactions})
    {
	#construct an array to hold the enzymes
	my @enzymes;
	
	#iterate through all entries and try to find an enzyme for this reaction
	foreach my $thisEntry (keys %{$self->{'data'}->{'entry'}})
	{
	   
	    #check if this entry has any part in the current reaction
	    if(($self->{'data'}->{'entry'} -> {$thisEntry} ->{'reaction'}) eq $thisReaction)
	    {
		push (@enzymes, $self->{'data'}->{'entry'} -> {$thisEntry} -> {'name'});
	    }
	}
	
	#map the current reaction to the array of enzymes
	$results -> {$thisReaction} = \@enzymes;
    }

    return $results;

}

# METHOD print_reaction_data
# prints the reaction data from the endpoints given
#
# takes (html, array of start points, array of end points)
# returns (nothing)
sub print_reaction_data
{
    my($self, $html, $cgi, $givenStartPoints, $givenEndPoints, $subsystem) = @_;
    my(@start, @end, $results_hash);

    @start = @{$givenStartPoints};
    @end = @{$givenEndPoints};

    $results_hash = $self -> find_many_links(\@start, \@end, $html);
	
    push(@$html,$cgi->br,$cgi->h4('Reaction Analysis'));
    foreach my $start (@{$givenStartPoints})
    {
	$start =~ s/ //g;    
	
	foreach my $end (@{$givenEndPoints})
	{		
	    $end =~ s/ //g;    
	    
	    foreach my $totalPaths (@{$results_hash -> {$start} -> {$end}})
	    {
		push(@$html, "$start --> ");
		
		foreach my $thisPath(@{$totalPaths})
		{
		    push(@$html, $thisPath . " --> ");
		}
		push(@$html, "$end<BR>");
		
		#get the enzyme associations and print them out
		my $enzyme_results_hash = $self -> associate_enzymes($html,$totalPaths);
		
		foreach my $thisPath(@{$totalPaths})
		{
		    push(@$html, "<B>$thisPath Enzymes: </b>");
		    
		    foreach my $thisEnzyme(@{$enzyme_results_hash -> {$thisPath}})
		    {
			push(@$html, $thisEnzyme . ", ");
			
		    }
		    
		    push(@$html, "<BR>");
		}
		push(@$html, "<BR>");
	    }
	}
	push(@$html, "<BR>");
    }
    
}



1;




####TO BE REMOVED########
#!
###get_matching_pathways_rns###
#
# Input: KGMLData Object, Directory path of xml files, Array of rn's to match for in the pathway
#
# Output: A array, each index containing another array of pathway title, a link, how many matches in it, and filepath.
# This has replaced best_matching_pathway. Use this for new code
###########################
sub get_matching_pathways_rns
{
	my($self,$dir,@rnIDs) = @_;
	my @results;
	my @xml_files = $self->get_xml_files_in_dir($dir);
	foreach my $file (@xml_files){
		$self->read_file($file,0);
		my $matchresults = $self->search_for_rns(@rnIDs)->{'match'};
		if(@$matchresults){
			my $link = $self->get_pathway_link();
			$link =~ s/map/rn/;
			my $count = 0;
			foreach my $rn (@$matchresults){
				$link = $link."+".$rn;
				$count++;
			}
			my @temp = ($self->current_pathway_number(),
				    $self->current_pathway_title(),$link,$count,$file);
			push(@results,\@temp);
		}
	}
	return \@results;
}

sub show_matching_pathways_rns
{	
	my($self,$subsystem,$cgi,$html) = @_;
	my $ssa  = $cgi->param('ssa_name');
	#print welcome header
	push(@$html,$cgi->h3("KEGG Pathway Reaction Relation"),"Subsystem: $ssa",$cgi->br);
	#get the subsystem EC numbers
	my @ecs = $self->roles_to_ec($subsystem->get_roles());
	my %hope_reactions = $subsystem->get_hope_reactions();
	my @rns;

	if (%hope_reactions)
	{
	    foreach my $role (keys %hope_reactions)
	    {
		push @rns, @{$hope_reactions{$role}};
	    }
	}
	push (@$html, "Found the following reactions: @rns\n");

	#if defined, lets continue, else print error
	if(@rns)
	{
		#get a list of the pathways with matches, their links, and how many EC's matched.
		my $matching_array;
		eval {$matching_array = $self->get_matching_pathways_rns($FIG_Config::kgml_dir."/map/",@rns)};
		if($@ || !defined $matching_array)
		{
			push(@$html, "No Results Found or Error: $@");
		}
		else{
			push(@$html,"Matching Pathways:",$cgi->br);
			foreach my $entry (@$matching_array){
				my($match_id,$linking_list,$to_add) = $self->ec_relation_analysis($subsystem,$entry->[4]);
				push(@$html,"<b>$entry->[0]</b>: $entry->[1] => ","<a href=\"$entry->[2]\">Current Hope Reactions in Pathway</a>",$cgi->br,$cgi->br);					
			}
		}		
	}
	else
	{
		push(@$html,"No Hope reaction ids in subsystem.");
	}

}
###get_data_set###
#
# Input: KGMLData Object
#
# Output: entire data structure of the xml document
##################
sub get_data_set()
{
	my ($self) = @_;
	#Get the reference, so we can dereference it, and return
	my $data_set_ref = $self->{'data'};
	return %$data_set_ref;
}

###get_reaction_sub_prod###
#
# Input: KGMLData Object, Reaction ID
#
# Output: hash containing the arrays of the subsrates and products of a reaction
###########################
sub get_reaction_sub_prod()
{
	my ($self,$reaction) = @_;
	return ('substrate' => $self->{'data'}{'reaction'}{$reaction}{'substrate'},
					'product' => $self->{'data'}{'reaction'}{$reaction}{'product'});	
}
###get_all_ids###
#
# Input: KGMLData Object
#
# Output: all the IDs of each entry in the xml file
#################
sub get_all_ids()
{
	my ($self) = @_;
	my @allids;
	my $hash = $self->{'data'}->{'entry'};
	my @returning = keys %$hash;
	return @returning;
}

#search_for_rns 
sub search_for_rns()
{
	my ($self, @rnlist) = @_;
	
	my @matched;
	my @missing;
	my %seen;
	$seen{""} = 1;
	my $reaction_set = $self->{'data'}{'reaction'};
	#loop through each entry element, checking for ec number matches
	foreach my $key (keys %$reaction_set)
	{			
		foreach my $rn (@rnlist)
		{
			#some names have the ec number, then orth data behind it, this takes just the first ec number
			#for accurate matching
##			my @temp = split(/\:/,$reaction_set->{$key}->{'name'});
			my @temp = split(/:/,$key);
			if($temp[1] eq $rn)
			{
				push(@matched,$rn) unless $seen{$rn}++;
			}
		}
	}	
	return {'match' => \@matched,'missing' => \@missing};	
}

# METHOD find_reaction_with_compound
# finds reactions given with compound ID
#
# takes( compound id )
#
# returns( array of reaction ID's)
sub find_reaction_with_compound
{
    my ($self, $id) = @_;
    my ( $reaction, $thisReaction, @reactions );

    #get  the reaction data
    $reaction = $self->{'data'} -> {'reaction'};
    
    #iterate throguh and get all of the reaction data for this compund
    foreach (keys %$reaction)
    {
	if($reaction -> {$_} -> {'substrate'} -> {'name'} eq $id)
	{
	    push (@reactions, $reaction -> {$_} -> {'name'});
	}

	elsif($reaction -> {$_} -> {'product'} -> {'name'} eq $id)
	{
	    push (@reactions, $reaction -> {$_} -> {'name'});
		}
    }		
	
    return \@reactions;
    
}

# METHOD get_reaction_substrate
# finds reactions given with compound ID
#
# takes( reaction name(KEGGID) )
#
# returns( array containing the product's ID )
sub get_reaction_substrate
{
    my($self, $reaction) = @_;

    return $self->{'data'} ->{'reaction'}-> {$reaction} -> {'substrate'} ;
}
sub get_start_pts
{
	my ($self, $html, $subsystem) = @_;
	my $startRef = $subsystem->get_start_points();
	
	push(@$html, $startRef);

	my @start = split (/,/,$startRef);

	return @start;
}

sub get_end_pts
{
	my ($self, $subsystem) = @_;
	my $endRef = $subsystem->get_end_points();
	my @end = split (/,/,$endRef);
	return @end;
}

