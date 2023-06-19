/* MyMetagenomicsAnnotation.js
 * Rob Edwards
 * June 1st
 *
 * Its magic
 */

var fn = {};
var allData = {};

var otu = {};
var cbk=0;
var xmlreqs = new Array(); 
var chunks = 0;
var displayLevel = 0;
var errorCount = 0;
var webServiceCallsSent = 0;
var webServiceCallsRecd = 0;
var seenFn = {};


var subsystemOne = {};
var subsystemTwo = {};
var subsystemThree = {};
var subsystemThreeTxt = {};
var subsystemOneCounts = {};
var subsystemTwoCounts = {};
var subsystemThreeCounts = {};

var subsystemsForFunc = {};

// hard code this if you need to. You will need to change the URL to avoid cross-site scripting errors
// var baseUrl =  location.host;
var baseUrl = "http://www.phantome.org/PhageSeed/";
// baseUrl = "http://bioseed.mcs.anl.gov/~redwards/FIG/";

function init() {
	// hide the file name!
	getSubsystems();
	document.getElementById('FileData').style.display="none";
	document.getElementById('primary').innerHTML = "<b>Thinking ...</b>";
	document.getElementById('errors').innerHTML = "<p><small>This is v.20</small></p>";
	var fileinfo = document.getElementById('FileData').value;
	var obj = JSON.parse(fileinfo);
	/* if (document.uploadmgx.useSubsystems.checked)
	   confirm("No");
	   else 
	   confirm("Yes");

	   obj= confirm("SS is " + useSS);
	 */

	// alert("Filename: " + obj['filename']);
	callWS(obj['filename'],obj['nseqs'],obj['reliability'],obj['kmer'],obj['maxGap']);
}

function callWS(filename, nseqs, reliability, kmer, maxGap) {

	chunks = nseqs;
	var count=0;
	var req=[];
	while (count < nseqs) {
		count++;

		var url = baseUrl + "rest_rtmg.cgi/annotate_fasta_file/" + filename + "." + count + "/" + reliability + "/" + kmer + "/" + maxGap;
		xmlreqGET(url);
	}
}


/*
 * parse - get the data back from the server and count how many things are there.
 */

function parse(obj) {
	cbk++;
	// confirm("Got " + obj);
	var data = JSON.parse(obj);

	var getSubsystems = [];

	var isTrue = true;
	for (arrid in data.result) {
		//if (isTrue) 
		//	isTrue = confirm("Checking " + data.result[arrid][0]);
		if (!allData[data.result[arrid][0]])
			allData[data.result[arrid][0]]=new Array();
		
		allData[data.result[arrid][0]].push(data.result[arrid][1]);

		
		var arr = data.result[arrid][1];
		if (fn[arr[3]])
			fn[arr[3]]++;
		else
			fn[arr[3]] = 1;

		// do we need to get the subsystem for this function
		if (!seenFn[arr[3]]) 
			getSubsystems.push(arr[3]);
		
		seenFn[arr[3]]=1;

		var thisOtu = arr[4];
		if (!thisOtu) 
			thisOtu = "Matches to organisms from diverse taxonomic branches<br></br><small>(so we can't assign them uniquely!)</small>";

		if (otu[thisOtu])
			otu[thisOtu]++;
		else
			otu[thisOtu] = 1;

		/*
		 * Count the subsystems.\
		 * we need to convert this function to a list of subsystems, and then count those
		 */

	}
	functionsToSubsystems(getSubsystems);
	showTable();
}


/* 
 * fn2subsystems - convert a function to a subsystem. Since we usually see > 1 count, we'll remember,
 */

function functionsToSubsystems(getSS) {
	var count=0;
	var toGet;
	for (idx in getSS) {
		count++;
		if (count > 10) {
			count=0;
			getFunctions(toGet);
			toGet = "";
		}

		var stringy = getSS[idx];
		if (stringy.indexOf("/") != -1)
			stringy = stringy.replace(/\//g,  "forwardslash");

		stringy = encodeURIComponent(stringy);
		toGet = toGet + "/" + stringy;	
	}
	getFunctions(toGet);
}

function getFunctions(listToGet) {
	var url = baseUrl + "rest_seed.cgi/functions_to_subsystems/" + listToGet;


	var xcall = false; 
	if (window.XMLHttpRequest) {
		xcall = new XMLHttpRequest();
	}
	else if (window.ActiveXObject) {
		xcall = new ActiveXObject("Microsoft.XMLHTTP");
	}
	try {
		xcall.open("GET",url,true);
	}
	catch(e) {
		alert("Error getting " + url);
	}

	xcall.onreadystatechange=function() {
		if(xcall.readyState==4) {
			parseFnToSubsystems(xcall.responseText);
		}
	}

	if (window.XMLHttpRequest) {
		xcall.send(null);
	}
	else if (window.ActiveXObject) {
		xcall.send();
	}
	showWSCalls(1);
}

function parseFnToSubsystems(obj) {
	showWSCalls(-1);
	var arr = JSON.parse(obj);
	for (idx in arr.result) {
		if (!subsystemsForFunc[idx])
			subsystemsForFunc[idx] = new Array();
		for (jdx in arr.result[idx])
			subsystemsForFunc[idx].push(arr.result[idx][jdx]);
		
		if (subsystemsForFunc[idx].length == 0)
			subsystemsForFunc[idx].push('Not yet in a subystem');
			
	}
	recount();
}


/* 
 * showtable - calculate the right order and redraw the table
 *
 */

function showTable() {

	// get the keys in reverse sorted order
	var keyArray = new Array();
	for (k in fn) 
		keyArray.push(k);

	keyArray.sort(function (a, b) {return fn[b] - fn[a]});

	var otuArray = new Array();
	for (o in otu)
		otuArray.push(o);

	otuArray.sort(function(a, b) {return otu[b] - otu[a]});


	var html = [];
	html.push("<h3>Click a column heading to sort the table.</h3>");
	html.push('<table class="sortable" id="theData">');
	var fnc;

	/*
	 * set th display for the apropriate level
	 * level 0 == function
	 * level 1 == subsystemOne
	 * level 2 == subsystemTwo
	 * level 3 == subsystemThree
	 * level 4 == otu's
	 */

	var total = 0;
	if (displayLevel == 0) {
		html.push("<thead><tr><th>Function</th><th>Count</th></tr></thead><tbody>");
		for (idx in keyArray) {
			var fnc = keyArray[idx];
			html.push("<tr><td>" + fnc + "</td><td>" + fn[fnc] + "</td></tr>");
			total = total + fn[fnc];
		}
	}
	else if (displayLevel == 1) {
		html.push("<thead><tr><th>Classification I</th><th>Count</th></tr></thead><tbody>");
		for (idx in subsystemOneCounts) {
			html.push("<tr><td>" + idx + "</td><td>" + subsystemOneCounts[idx] + "</td></tr>");
			total += subsystemOneCounts[idx];
		}
	}
	else if (displayLevel == 2) {
		html.push("<thead><tr><th>Classification I</th><th>Classification II</th><th>Count</th></tr></thead><tbody>");
		for (idx in subsystemTwoCounts) {
			html.push("<tr><td>" + idx + "</td><td>" + subsystemTwoCounts[idx] + "</td></tr>");
			total += subsystemTwoCounts[idx];
		}
	}
	else if (displayLevel == 3) {
		html.push("<thead><tr><th>Classification I</th><th>Classification II</th><th>Subsystem Name</th><th>Count</th></tr></thead><tbody>");
		for (idx in subsystemThreeCounts)  {
			html.push("<tr><td>" + idx + "</td><td>" + subsystemThreeCounts[idx] + "</td></tr>");
			total += subsystemThreeCounts[idx];
		}
	}
	else if (displayLevel == 4) {
		html.push("<thead><tr><th>OTU</th><th>Count</th></tr></thead><tbody>");
		for (idx in otuArray) {
			var thisOtu = otuArray[idx];
			html.push("<tr><td>" + thisOtu + "</td><td>" + otu[thisOtu] + "</td></tr>");
			total += otu[thisOtu];
		}
	}

	html.push("</tbody><tfoot><tr><th>Total</th><th>" + total + "</th></tr></tfoot>");
	html.push("</table>");
	
	document.getElementById('primary').innerHTML = html.join('');
	
	// update progress
	showWSCalls(0);
	
	var saveHtml = [];
	saveHtml.push("<p>To save this table, please click on the 'export table' button. It will open a new window (sorry, you may need to allow this site to pop up windows) ");
	saveHtml.push("with the table in it. You can then use your Browser's 'Save As' option from the file menu to save the data. Save it with the extension .txt or .xls ");
	saveHtml.push("and you can open it in OpenOffice or Excel.</p>");
	saveHtml.push('<p><input type="button" value="Export Table" onClick="writeExcel(); return false;"></input></p>');
	document.getElementById('saveBox').innerHTML = saveHtml.join('');

	var saveHits = [];
	saveHits.push("<p>To save the hits, please click on the Export Hits button. This will open a new window (sorry, as before), and will make a table of the ");
	saveHits.push("sequence IDs, their proposed functions, and the subsystems to which they belong. This is tab separated text, so you can copy and paste it ");
	saveHits.push("in to your favorite program, or write your own code to analyze those sequences. For some reason, I can't get this save as to work here!</p>");
	saveHits.push('<p><input type="button" value="Export Hits" onClick="writeHits(); return false;"></input></p>');
	document.getElementById('saveHits').innerHTML = saveHits.join('');

	var saveJson = [];
	saveJson.push("<p>To save the output in JSON format, please click the Export Json button. This will open a new window (sorry, as before), that will contain ");
	saveJson.push("a bunch of mostly unreadable text, but the computers know how to handle this. You can share this on orkut with our metagenomics app.</p>");
	saveJson.push('<p><input type="button" value="Export Json" onClick="writeJson(); return false;"></input></p>');
	document.getElementById('saveJson').innerHTML = saveJson.join('');

	// now that we have rendered the table, we need to make it sortable
	sorttable.makeSortable(document.getElementById('theData'));
	recount(); // recount everything!
}


function writeJson() {
	var output = {};
	if (displayLevel == 0) {
		// get the keys in reverse sorted order
		var keyArray = new Array();
		for (k in fn) 
			keyArray.push(k);

		keyArray.sort(function (a, b) {return fn[b] - fn[a]});


		for (idx in keyArray) {
			var fnc = keyArray[idx];
			output[fnc] = fn[fnc];
		}
	}
	else if (displayLevel == 1) {
		for (idx in subsystemOneCounts) {
			output[idx] = subsystemOneCounts[idx];
		}
	}
	else if (displayLevel == 2) {
		for (idx in subsystemTwoCounts) {
			output[idx] = subsystemTwoCounts[idx];
		}
	}
	else if (displayLevel == 3) {
		for (idx in subsystemThreeCounts)  {
			output[idx] = subsystemThreeCounts[idx];
		}
	}
	else if (displayLevel == 4) {
		var otuArray = new Array();
		for (o in otu)
			otuArray.push(o);

		otuArray.sort(function(a, b) {return otu[b] - otu[a]});
		for (idx in otuArray) {
			var thisOtu = otuArray[idx];
			output[thisOtu] = otu[thisOtu];
		}
	}

	var JsonText = JSON.stringify(output);
	var winRef =window.open('','Your Data',
			'width=350,height=250'
			+',menubar=1'
			+',toolbar=1'
			+',status=1'
			+',scrollbars=1'
			+',resizable=1');

	winRef.document.writeln(JsonText);
	winRef.document.close();
}

function writeExcel() {
	var tableHtml = document.getElementById('theData').innerHTML;
	var winRef =window.open('','Your Data',
			'width=350,height=250'
			+',menubar=1'
			+',toolbar=1'
			+',status=1'
			+',scrollbars=1'
			+',resizable=1');

	// var docRef = winRef.document.open("text/html","replace");
	//var docRef = winRef.document.open("application/vnd.ms-excel","replace");

	winRef.document.writeln("<html><head><title>Your Annotated Metagenome</title><body><table>" + tableHtml + "</table></body></html>");
	// docRef.getElementById('theTable').innerHTML = tableHtml;
	// winRef.document.getElementById('theTable').innerHTML = tableHtml;
	winRef.document.close();

}

/* 
 * writeHits() - we're going to print out all the hits and their three level subsystems in one single new window.
 * Leave it up to the user to explore what that means
 *
 */

function writeHits() {
	var tableHtml = [];
	tableHtml.push("Sequence ID\tStart of hit\tEnd of hit\tOTU\tFunction\tLevel 1\tLevel 2\tSubsystem");
	var isTrue = true;
	for (seqId in allData) {

		for (idx in allData[seqId]) {
			var numHits = allData[seqId][idx][0];
			var start   = allData[seqId][idx][1];
			var end     = allData[seqId][idx][2];
			var fnc     = allData[seqId][idx][3];
			var otu     = allData[seqId][idx][4];
			for (idx in subsystemsForFunc[fnc]) {
				var ss = subsystemsForFunc[fnc][idx];
				tableHtml.push(seqId + "\t" + start + "\t" + end + "\t" + otu + "\t" + fnc + "\t" + subsystemThreeTxt[ss]);
			}
		}
	}

	var winRef =window.open('','Your Data', 'width=350,height=250,menubar=1,toolbar=1,status=1,scrollbars=1,resizable=1');

	winRef.document.open("text/plain");
	winRef.focus();

	winRef.document.write(tableHtml.join("\n"));
	winRef.document.close();
}

function OldwriteHits() {
	var tableHtml = [];
	tableHtml.push("<tr><th>Sequence ID</th><th>Number of hits</th><th>Start of hit</th><th>End of hit</th><th>OTU</th><th>Function</th>");
	tableHtml.push("<th>SS1</th><th>SS2</th><th>Subsystem</th></tr>");
	var isTrue = true;
	for (seqId in allData) {

		for (idx in allData[seqId]) {
			var numHits = allData[seqId][idx][0];
			var start   = allData[seqId][idx][1];
			var end     = allData[seqId][idx][2];
			var fnc     = allData[seqId][idx][3];
			var otu     = allData[seqId][idx][4];
			for (idx in subsystemsForFunc[fnc]) {
				var ss = subsystemsForFunc[fnc][idx];
				if (isTrue)
					isTrue =confirm('Start: "' + start + '" END: "' + end + '" num: "' + numHits + '"');
				tableHtml.push("<tr><td>" + seqId + "</td><td>" + numHits + "</td><td>" + start + "</td><td>" + end);
				tableHtml.push("</td><td>" + otu + "</td><td>" + fnc + "</td><td>" + subsystemThree[ss] + "</td></tr>");
			}
		}
	}

	var winRef =window.open('','Your Data',
			'width=350,height=250'
			+',menubar=1'
			+',toolbar=1'
			+',status=1'
			+',scrollbars=1'
			+',resizable=1');
	winRef.document.writeln("<html><head><title>Your Annotated Metagenome</title><body><table>" + tableHtml.join('') + "</table></body></html>");
	winRef.document.close();
}


/*
 * getSubsystems()
 * 
 * get the subsystems using a ws call, and store the two level hierarchy
 *
 */

function getSubsystems() {
	var url = baseUrl + "rest_seed.cgi/all_subsystem_classifications";
	var xcall = false; 
	if (window.XMLHttpRequest) {
		xcall = new XMLHttpRequest();
	}
	else if (window.ActiveXObject) {
		xcall = new ActiveXObject("Microsoft.XMLHTTP");
	}
	showWSCalls(1);
	xcall.open("GET",url,true);
	xcall.onreadystatechange=function() {
		if(xcall.readyState==4) {
			parseSubsystems(xcall.responseText);
			showWSCalls(-1);
		}
	}

	if (window.XMLHttpRequest) {
		xcall.send(null);
	}
	else if (window.ActiveXObject) {
		xcall.send();
	}
}

function parseSubsystems(obj) {
	var subsystemslist = JSON.parse(obj);
	// var istrue=true;
	// istrue = confirm("2got " + ss0 + " and " + ss1 + " and " + ss2);
	// if (!istrue)
	// break;

	// handle the cases where things are not in subsystems
	subsystemOne['Not yet in a subystem'] =  'Not yet in a subsystem';
	subsystemTwo['Not yet in a subystem'] = "Not yet in a subsystem</td><td>-";
	subsystemThree['Not yet in a subystem'] = "-</td><td>-</td><td>Not yet in a subsystem";

	for (i in subsystemslist.result) {
		var ss0 = subsystemslist.result[i][0];
		var ss1 = subsystemslist.result[i][1];
		var ss2 = subsystemslist.result[i][2];

		if (!ss0) ss0 = '-';
		if (!ss1) ss1 = '-';

		subsystemOne[ss2] = ss0;
		subsystemTwo[ss2] = ss0 + "</td><td>" + ss1;
		subsystemThree[ss2] = ss0 + "</td><td>" + ss1 + "</td><td>" + ss2;
		subsystemThreeTxt[ss2] = ss0 + "\t" + ss1 + "\t" + ss2;
		// subsystemTwo[ss2] = ss0 + "; " + ss1;
		// subsystemThree[ss2] = ss0 + "; " + ss1 + "; " + ss2;
	}

	/*
	 * now we have to count everything in case we already got a bunch of stuff
	 */

	recount();
}



function recount() {
	// reset all arrays:
	subsystemOneCounts = {};
	subsystemTwoCounts = {};
	subsystemThreeCounts = {};

	for (fnc in fn) {
		subsystemCountFunctions(subsystemOne, subsystemOneCounts, fnc);
		subsystemCountFunctions(subsystemTwo, subsystemTwoCounts, fnc);
		subsystemCountFunctions(subsystemThree, subsystemThreeCounts, fnc);
	}
}



/*
 * Function count the subsystems. Takes the array of subsystems as the first obj
 * the array of subsystem counts as the second object
 * and the func as the third
 *
 */

function subsystemCountFunctions(ssarray, sscounts, fn) {
	// the subsystems are a list in subsystemsForFunc[fn]
	for (idx in subsystemsForFunc[fn]) {
		var ss = subsystemsForFunc[fn][idx];
		if (ssarray[ss])
			if (sscounts[ssarray[ss]]) 
				sscounts[ssarray[ss]]++;
			else
				sscounts[ssarray[ss]]=1;
		else
			if (sscounts["Unknown"])
				sscounts["Unknown"]++;
			else 
				sscounts["Unknown"]=1;
	}
}


/*
 * setDisplayLevel : whether we should show subsystems or functions (or both)
 */

function setDisplayLevel(l) {
	level = l.value;
	if (level < 0 || level > 4)
		return null;
	displayLevel = level;
	showTable();
}







/* 
 * Functions to make multiple simultaneous calls.
 * Basically a global array of individual calls. 
 * I almost had this working myself, but then found this elegant code online
 * so I used that!
 */


function CXMLReq(freed) {
	this.freed = freed;
	this.xmlhttp = false;
	if (window.XMLHttpRequest) {
		this.xmlhttp = new XMLHttpRequest();
	}
	else if (window.ActiveXObject) {
		this.xmlhttp = new ActiveXObject("Microsoft.XMLHTTP");
	}
}


function xmlreqGET(url) {
	var pos = -1;
	for (var i=0; i<xmlreqs.length; i++) {
		if (xmlreqs[i].freed == 1) {
			pos = i;
			break;
		}
	}

	if (pos == -1) {
		pos = xmlreqs.length;
		xmlreqs[pos] = new CXMLReq(1);
	}

	if (xmlreqs[pos].xmlhttp) {
		xmlreqs[pos].freed = 0;
		xmlreqs[pos].xmlhttp.open("GET",url,true);
		xmlreqs[pos].xmlhttp.onreadystatechange = function() {
			if (typeof(xmlhttpChange) != 'undefined') {
				xmlhttpChange(pos);
			}
		}
		if (window.XMLHttpRequest) {
			xmlreqs[pos].xmlhttp.send(null);
		}
		else if (window.ActiveXObject) {
			xmlreqs[pos].xmlhttp.send();
		}
	}
}

function xmlhttpChange(pos) {
	if (typeof(xmlreqs[pos]) != 'undefined' && xmlreqs[pos].freed == 0 && xmlreqs[pos].xmlhttp.readyState == 4) {
		if (xmlreqs[pos].xmlhttp.status == 200 || xmlreqs[pos].xmlhttp.status == 304) {
			parse(xmlreqs[pos].xmlhttp.responseText);
		}
		else {
			document.getElementById('errors').innerHTML = "<p>Error getting file at " + pos + " for url " + xmlreqs[pos].xmlhttp.url + "</p>";
		}
		xmlreqs[pos].freed = 1;
	}

}


function showWSCalls(idx) {
	
	// an index of 1 means we have sent one, an index of -1 means
	// we have received one. An index of 0 means we don't want to count this
	// one, we just want to update the display.
	
	if (idx == 1)
		webServiceCallsSent++;
	else if (idx == -1)
		webServiceCallsRecd++;
	
	
	var html = [];
	// Calculate the percent of assignments done
	var percent = cbk/chunks * 10000;
	percent = parseInt(percent) || 0;
	var p = percent / 100;

	if (p == 100) 
		html.push("<h3>Assigning functions to sequences: complete</h3>");
	else
		html.push("<h3>Assigning functions to sequences: " + p + " % complete</h3>");
	
	
	percent = webServiceCallsRecd/webServiceCallsSent * 10000;
	percent = parseInt(percent);
	p = percent / 100;

	if (p == 100)
		html.push("<h3>Assigning functions to subsystems: complete</h3>");
	else
		html.push("<h3>Assigning functions to subsystems: " + p + " % complete</h3>");
	

	document.getElementById('wsCalls').innerHTML = html.join("\n");
	
/*
	if (webServiceCalls > 0) 
		document.getElementById('wsCalls').innerHTML = "The annotation process is gathering subsystems for functions.<br></br>There  are " + webServiceCalls + " functions waiting to be placed";
	else
		document.getElementById('wsCalls').innerHTML = "Not waiting for anything. Yeah!";
	*/
}



