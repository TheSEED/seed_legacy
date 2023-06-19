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


function setActiveStyleSheet(title) {
  var i, a, main;
  for(i=0; (a = document.getElementsByTagName("link")[i]); i++) {
    if(a.getAttribute("rel").indexOf("style") != -1 && a.getAttribute("title")) {
      a.disabled = true;
      if(a.getAttribute("title") == title) a.disabled = false;
    }
  }
}


