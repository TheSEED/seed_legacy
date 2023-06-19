//
//  GenomeSelector.js  --  Action scripts for GenomeSelector.pm
//

//
// Copyright (c) 2003-2013 University of Chicago and Fellowship
// for Interpretations of Genomes. All Rights Reserved.
//
// This file is part of the SEED Toolkit.
//
// The SEED Toolkit is free software. You can redistribute
// it and/or modify it under the terms of the SEED Toolkit
// Public License.
//
// You should have received a copy of the SEED Toolkit Public License
// along with this program; if not write to the University of Chicago
// at info@ci.uchicago.edu or the Fellowship for Interpretation of
// Genomes at veronika@thefig.info or download a copy from
// http://www.theseed.org/LICENSE.TXT.
//

function update_genomes( form, param )
{
    var genlistname = param + '_current';
    form[genlistname] = sort_genomes( form, genome_set( form, param ) );
    filter_and_show_genomes( form, param );
}


//
//  Each genome is defined by an Array object:
//
//     0    1      2        3        4         5           6               7                8
//  [ gid, name, domain, contigs, complete, plasmid, name_sort_order, tax_sort_order, gid_sort_order ]
//
function genome_set( form, param )
{
    var archaea  = form.ShowArchaea.checked;
    var bacteria = form.ShowBacteria.checked;
    var eucarya  = form.ShowEucarya.checked;
    var viruses  = form.ShowViruses.checked;
    var plasmids = form.ShowPlasmid.checked;
    var unclass  = form.ShowUnclass.checked;
    if ( ! ( archaea || bacteria || eucarya || viruses || plasmids || unclass ) )
    {
        archaea  = true;
        bacteria = true;
        eucarya  = true;
    }
    var partial  = form.ShowPartial.checked;

    var genlistname = param + '_genomes';
    var allgens     = form[genlistname];
    var mygens      = new Array();
    for ( var i = 0; i < allgens.length; i++ )
    {
        var g = allgens[i];
        // Deal with genomes that are not screened for completeness
        var is_plasmid = g[5] || ( g[2] == "P" );
        if ( is_plasmid  ) { if ( plasmids ) { mygens.push( g ) } continue }
        if ( g[2] == "V" ) { if ( viruses )  { mygens.push( g ) } continue }
        if ( g[2] == "Z" ) { if ( unclass )  { mygens.push( g ) } continue }
        if ( g[4] || partial )
        {
            switch ( g[2] )
            {
                case "A": if ( archaea  ) { mygens.push( g ) } break
                case "B": if ( bacteria ) { mygens.push( g ) } break
                case "E": if ( eucarya  ) { mygens.push( g ) } break
                default:  if ( unclass  ) { mygens.push( g ) } 
            }
        }
    }
    return mygens;
}


function filter_and_show_genomes( form, param )
{
    var genlist;
    var curlistname = param + '_current';
    var genlistname = param + '_genomes';
    if ( form.TextFilter.value.length )
    {
        var gens = form[curlistname];
        var filter = new RegExp( form.TextFilter.value, "i" );
        genlist = new Array();
        for ( var i = 0; i < gens.length; i++ )
        {
            if ( filter.test( gens[i][1] ) ) { genlist.push( gens[i] ) }
        }
    }
    else
    {
        genlist = form[curlistname];
    }

    var optlist = form[param].options;
    var order   = radio_value( form.SortBy );
    
    optlist.length = 0;
    for ( var i = 0; i < genlist.length; i++ )
    {
        optlist[i] = genome_option( genlist[i], order );
    }
    var counttext = document.getElementById(form.name + "_" + param + "_GenCount");
    counttext.innerHTML = optlist.length + " of " + form[genlistname].length + " genomes";
}


function sort_genomes( form, genomes )
{
    switch ( radio_value( form.SortBy ) )
    {
        case "name":  genomes.sort( by_name     ); break
        case "taxon": genomes.sort( by_taxonomy ); break
        case "gid":   genomes.sort( by_gid      ); break
    }
    return genomes;
}

function by_name(a,b)     { return a[6] - b[6] }
function by_taxonomy(a,b) { return a[7] - b[7] }
function by_gid(a,b)      { return a[8] - b[8] }


//
//  Build an Option object and cache it in the genome Array.
//  There are two separate forms: name first (g[9]) and gid first (g[10]).
//
function genome_option( g, order )
{
    if ( ! order ) { order = "name" }
    var text = ( order == "gid" ) ? g[0] + String.fromCharCode(32,0x2014,32) + g[1] + " [" + g[3] + " contigs]"
                                  : g[1] + " (" + g[0] + ") [" + g[3] + " contigs]";
    return new Option( text, g[0] );
}


//
//  Find the value of the selected radio button
//
function radio_value( radio )
{
    for ( var i = 0; i < radio.length; i++ )
    {
        if ( ! radio[i].checked ) { continue }
        return radio[i].value;
    }
    return null;
}


//
//  Escape text that will be used as HTML -- currently not used
//
var entityMap = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };

function escape_html( string )
{
    return String(string).replace( /[&<>]/g, function(s) { return entityMap[s] } );
}
