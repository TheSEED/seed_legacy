//
// Copyright (c) 2003-2006 University of Chicago and Fellowship
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


function ActiveDiagram(map_div_id)
{
    this.map_div_id = map_div_id;

//    var consoleService = Components.classes['@mozilla.org/consoleservice;1']
//    .getService(Components.interfaces.nsIConsoleService);

//    consoleService.logStringMessage("Have  self ", this);


    var detect = navigator.userAgent.toLowerCase();


    if (detect.indexOf("msie") >= 0)
    {
//	alert("is IE");
	this.classAttribute = "className";
    }
    else
    {
	this.classAttribute = "class";
    }
    this.roleList = new Array;
    this.alternateList = new Array;
    this.complexList = new Array;		

}
new ActiveDiagram(null, null);

ActiveDiagram.prototype.load = function()
{
    //alert("loading diagram");
    var elts, container, i;
    elts = document.getElementsByTagName("map");
    container = document.getElementById(this.map_div_id);

    var compoundRE = /C\d+/;

    for (i = 0; i < elts.length; i++)
    {
	var map, anum;
        
	map = elts[i];
	
	for (anum = 0; anum < map.areas.length; anum++)
	{
	    var area;
	    area = map.areas[anum];
            
	    var role = area.getAttribute("Role");
	    var compound = area.getAttribute("Compound");
	    var alternate = area.getAttribute("Alternate");
	    var complex = area.getAttribute("Complex");	

	    if (role != null && area.shape.toLowerCase() == "rect")
	    {
        	//alert("going thru digram on load");
                //alert(role);
		var clist = area.coords.split(",");
		
		var div = document.createElement("div");

		this.roleList[this.roleList.length] = div;
	    
		div.setAttribute("id", "area_" + anum);
		div.setAttribute(this.classAttribute, "transparent");
	        div.setAttribute("areaType", "role");
		div.setAttribute("role", role);

		var style = div.style;
		style.position = "absolute";
		style.left = new String(clist[0]) + "px";
		style.top = new String(clist[1]) + "px";
		style.width = new String(clist[2] - clist[0]) + "px";
		style.height = new String(clist[3]- clist[1]) + "px";

		container.appendChild(div);
	    }

            if (alternate != null && area.shape.toLowerCase() == "rect")
	    {
		//alert("alternate found!");
                //alert(alternate); 
		var clist = area.coords.split(",");
		
		var div = document.createElement("div");

		this.alternateList[this.alternateList.length] = div;
	        //alert("div1");
                //alert(div);
		div.setAttribute("id", "area_" + anum);
		div.setAttribute(this.classAttribute, "transparent");

		div.setAttribute("areaType", "alternate");
		div.setAttribute("alternate", alternate);
		//alert("adding to list");
                //alert(alternate);
		var style = div.style;
		style.position = "absolute";
		style.left = new String(clist[0]) + "px";
		style.top = new String(clist[1]) + "px";
		style.width = new String(clist[2] - clist[0]) + "px";
		style.height = new String(clist[3]- clist[1]) + "px";

		container.appendChild(div);
	    }

            if (complex != null && area.shape.toLowerCase() == "rect")
	    {
		var clist = area.coords.split(",");
		
		var div = document.createElement("div");

		this.complexList[this.complexList.length] = div;
	    
		div.setAttribute("id", "area_" + anum);
		div.setAttribute(this.classAttribute, "transparent");

		div.setAttribute("areaType", "complex");
		div.setAttribute("complex", complex);

		var style = div.style;
		style.position = "absolute";
		style.left = new String(clist[0]) + "px";
		style.top = new String(clist[1]) + "px";
		style.width = new String(clist[2] - clist[0]) + "px";
		style.height = new String(clist[3]- clist[1]) + "px";

		container.appendChild(div);
	    }

	    if (compound != null)
	    {
		var url;

		if (compoundRE.exec(compound))
		{
		    url = "http://www.genome.ad.jp/dbget-bin/www_bget?cpd:" + compound;
		}
		else
		{
		    url = "http://www.genome.ad.jp/dbget-bin/www_bfind_sub?dbkey=compound&keywords=" + compound + "&mode=bfind&max_hit=1000";
		}
		    
		area.href = url;
		area.target = "compoundViewer";
		area.removeAttribute("nohref");
		area.removeAttribute("compound");
	    }
	}
    }
//    alert(container.innerHTML);
}

ActiveDiagram.prototype.colorRoles = function (rolesToColor)
{
    //alert("called colorRoles");
    var roleAssoc = new Object();
    var role;
        
    for (roleI in rolesToColor)
    {
       	role = rolesToColor[roleI];
        //alert("role name to color");
        //alert(role);
       	roleAssoc[role] = 1;
    }

    var i;

//    document.write("Here " + this.roleList + "<br>");
	
    for (i = 0; i < this.roleList.length; i++)
    {
        var div;
	div = this.roleList[i];
       	role = div.getAttribute("role");
        //alert("going thru list of roles on diagram");
        //alert(role);
       
	if (roleAssoc[role])
	{
//	document.write(role + " " + div + "<br>");
	    div.setAttribute(this.classAttribute, "colored");
            //alert("coloring role on diagram green");
       	}
	else
	{
	    div.setAttribute(this.classAttribute, "transparent");
            //alert("not coloring role on diagram green"); 
         } 
    }

    //alert("just before processing of alternate list");
    for (i = 0; i < this.alternateList.length; i++)
    {
        //alert(this.alternateList.length);
	var div;
	div = this.alternateList[i];
        //alert("div");
        //alert(div);
	alternate = div.getAttribute("alternate");
	var one_alternateList = alternate.split(",");
        var color_status = 0;
        //alert(alternate);

        for (j = 0; j < one_alternateList.length; j++)
	{
		var one;
		one = one_alternateList[j];
                //alert("one");
                //alert(one);   
		
		if (roleAssoc[one])
		{	
		    color_status = 1;
		}
    	}

        if(color_status){
        	div.setAttribute(this.classAttribute, "colored");
        }
	else
	{
		div.setAttribute(this.classAttribute, "transparent");
	}
    }

    //alert("just done processing alternateList");

    for (i = 0; i < this.complexList.length; i++)
    {
	var div;
	div = this.complexList[i];
	complex = div.getAttribute("complex");
	var one_complexList = complex.split(",");
        var color_status = 1;

        for (j = 0; j < one_complexList.length; j++)
	{
		var one;
		one = one_complexList[j];
		
		if (!roleAssoc[one])
		{	
		    color_status = 0;
		}
    	}

        if(color_status){
        	div.setAttribute(this.classAttribute, "colored");
        }
	else
	{
		div.setAttribute(this.classAttribute, "transparent");
	}
    }
}

ActiveDiagram.prototype.colorRedRoles = function (rolesToColor)
{
    //alert("colorRedRoles called");
    var rolesToColorString = new String(rolesToColor);
    var rolesToColorArray = rolesToColorString.split(",");
  
    var roleAssoc = new Object();
    var role;
    var roleI;
    
    for (roleI in rolesToColorArray)
    {
      	role = rolesToColorArray[roleI];
      	roleAssoc[role] = 1;
    }

    var i;

//    document.write("Here " + this.roleList + "<br>");
	
    for (i = 0; i < this.roleList.length; i++)
    {
        var div;
	div = this.roleList[i];
       	role = div.getAttribute("role");
     
	if (roleAssoc[role])
	{
       //   document.write(role + " " + div + "<br>");
	    div.setAttribute(this.classAttribute, "coloredRed");
         }
    }
}

ActiveDiagram.prototype.colorGreenRoles = function (rolesToColor)
{
    var rolesToColorString = new String(rolesToColor);
    var rolesToColorArray = rolesToColorString.split(",");
    var roleAssoc = new Object();
    var role;
    var roleI;
    
    for (roleI in rolesToColorArray)
    {
	role = rolesToColorArray[roleI];
	roleAssoc[role] = 1;
    }

    var i;

//    document.write("Here " + this.roleList + "<br>");
	
    for (i = 0; i < this.roleList.length; i++)
    {
       	var div;
	div = this.roleList[i];
       	role = div.getAttribute("role");

	if (roleAssoc[role])
	{
//	document.write(role + " " + div + "<br>");
	    div.setAttribute(this.classAttribute, "coloredGreen");
	}
    }
}

ActiveDiagram.prototype.colorBlueRoles = function (rolesToColor)
{
    var rolesToColorString = new String(rolesToColor);
    var rolesToColorArray = rolesToColorString.split(",");
    var roleAssoc = new Object();
    var role;
    var roleI;
    
    for (roleI in rolesToColorArray)
    {
	role = rolesToColorArray[roleI];
	roleAssoc[role] = 1;
    }

    var i;

//    document.write("Here " + this.roleList + "<br>");
	
    for (i = 0; i < this.roleList.length; i++)
    {
       	var div;
	div = this.roleList[i];
       	role = div.getAttribute("role");

	if (roleAssoc[role])
	{
//	document.write(role + " " + div + "<br>");
	    div.setAttribute(this.classAttribute, "coloredBlue");
	}
    }
}

ActiveDiagram.prototype.colorGrayRoles = function (rolesToColor)
{
    var rolesToColorString = new String(rolesToColor);
    var rolesToColorArray = rolesToColorString.split(",");
    var roleAssoc = new Object();
    var role;
    var roleI;
    
    for (roleI in rolesToColorArray)
    {
	role = rolesToColorArray[roleI];
	roleAssoc[role] = 1;
    }

    var i;

//    document.write("Here " + this.roleList + "<br>");
	
    for (i = 0; i < this.roleList.length; i++)
    {
        var div;
	div = this.roleList[i];
       	role = div.getAttribute("role");

	if (roleAssoc[role])
	{
//	document.write(role + " " + div + "<br>");
	    div.setAttribute(this.classAttribute, "coloredGray");
	}
    }
}
