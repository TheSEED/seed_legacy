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

###KGML Event Handler####
#
# This is an Event Handler for the PerlSAX XML Parser to parse KEGG KGML files.
#
# Author: Kevin Formsma , kevin.formsma@hope.edu
# Hope College, Summer 05 REU Research
#########################

package KGML;

use strict;

use XML::Parser::PerlSAX;

##Module Variables

my %recent_data;

#Data Storage for the parsing
	my @element_stack;   # remembers element names
	my $in_intset;	# flag: are we in the internal subset?
	my %pathway_hash; #copy of the pathway element attributes
	my %entry_hash; #array of all the enzyme elements and pathway elements, each element is hash of enzyme properties.

	my %current_entry;
	my %current_relation;
	my %current_reaction;
		
	my %relation_hash;
	my %reaction_hash;
	my @relation_list;
	
	my $count = 0;
	
	
	
#KGML Object Constructor
sub new {

%recent_data = ();
@element_stack = ();
$in_intset = ();
%pathway_hash = ();
%entry_hash = ();
%current_entry = ();
%current_relation = ();
%current_reaction = ();
%relation_hash = ();
%reaction_hash = ();
@relation_list = ();
$count = 0;

my $type = shift;
    return bless {}, $type;
}

#Handle events for readfile for the SAX parser
sub start_element{
	my( $self, $properties ) = @_;
	
	# close internal subset if still open
    output( "]>\n" ) if( $in_intset );
    $in_intset = 0;
    
    #get the attributes
    my %attributes = %{$properties->{'Attributes'}};
    
    #print "\n $properties->{'Name'} is open";
  
    # remember the name by pushing onto the stack
    push( @element_stack, $properties->{'Name'} );
    #add to main element, a pathway to the hash
    if($properties->{'Name'} eq "pathway")
    {
    	%pathway_hash = %attributes;
    }
    #If we have a graphics element, add it to the current entry element.
    elsif($properties->{'Name'} eq "graphics")
    {
    	$current_entry{'graphics'} = \%attributes;    	
    }
    #If we have a componet element, add it to the current entry element.
    elsif($properties->{'Name'} eq "component")
    {
    	$current_entry{'component'} = \%attributes;
    }
    #Set as current entry element.
    elsif($properties->{'Name'} eq "entry")
    {
    	%current_entry = %attributes;
    }
    elsif($properties->{'Name'} eq "relation")
    {
    	%current_relation = %attributes;
    }
    elsif($properties->{'Name'} eq "subtype")
    {
    	$current_relation{'subtype'} = \%attributes;
    }
    elsif($properties->{'Name'} eq "reaction")
    {
    	%current_reaction = %attributes;
    	$current_reaction{'substrate'} = ();
    	$current_reaction{'product'} = ();
    }
    elsif($properties->{'Name'} eq "substrate")
    {
    	my $temp = $current_reaction{'substrate'};
    	push(@$temp, $attributes{'name'});
    	$current_reaction{'substrate'} = $temp;
    }
    elsif($properties->{'Name'} eq "product")
    {
    	my $temp = $current_reaction{'product'};
    	push(@$temp, $attributes{'name'});
    	$current_reaction{'product'} = $temp;
    }
    elsif($properties->{'Name'} eq "alt")
    {
    	$current_reaction{'alt'} = \%attributes;
    }    
}

sub end_element{
	my( $self, $properties) = @_;
	
	# close internal subset if still open
    output( "]>\n" ) if( $in_intset );
    $in_intset = 0;
    
    #print "\n $properties->{'Name'} is closing now";
       
    #get the attributes
    
    if($properties->{'Name'} eq "entry")
    {
    	my %attributes = %current_entry;
    	%current_entry = ();    			
		$entry_hash{$attributes{'id'}} = \%attributes unless defined $attributes{'map'};    	
    }
    elsif($properties->{'Name'} eq "relation")
    {
    	my %attributes = %current_relation;    	   	
    	%current_relation = ();  
    	#print "\nStoring: $attributes{'entry1'} to $attributes{'entry2'}";
    	push(@relation_list, \%attributes);
    	
    	
		#my $relation_list =	$relation_hash{$attributes{'entry1'}};
		#push(@$relation_list,\%attributes);
		#$relation_hash{$attributes{'entry1'}} = $relation_list;
		
		#print "\n\nTEST.";
		#print "\nThis is whats related $attributes{'entry1'} to ...";
		#my $list = $relation_hash{$attributes{'entry1'}};
		#foreach my $element (@$list){
		#	print "\n".$element->{'entry2'};
		#}
    }
    elsif($properties->{'Name'} eq "reaction")
    {
    	my %attributes = %current_reaction;    	 	
    	#clear Current graphic and componet variables    	
    	%current_reaction = ();    	
		
		$reaction_hash{$attributes{'name'}} = \%attributes;
    }
    
    pop( @element_stack );
}

sub end_document{
	#my %recent_data;	
	#setup all data into one hashmap
	%recent_data = ('entry' => \%entry_hash,
				    'pathway' => \%pathway_hash,
				    'relation' => \@relation_list,
				    'reaction' => \%reaction_hash
				   );
}

sub return_data{
	return %recent_data;
	
}

1;
