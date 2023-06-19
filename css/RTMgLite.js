/* RTMg Lite
 * Rob Edwards
 * September 21st.
 *
 * Its magic
 */

var xmlreqs = new Array(); 
var tableHtml;
var jobId;
var level = 3;
var sent = 0;
var recd = 0;
var kmerDataset;
var timerCounter=1;
var timer;
var responseData;

// hard code this if you need to. You will need to change the URL to avoid cross-site scripting errors
// var baseUrl =  location.host;
var baseUrl = "http://www.phantome.org/PhageSeed/";
// baseUrl = "http://bioseed.mcs.anl.gov/~redwards/FIG/";

function init() {
	// hide the file name!
	document.getElementById('FileData').style.display="none";
	document.getElementById('primary').innerHTML = "<b>Thinking ...</b>";
	document.getElementById('errors').innerHTML = "<p><small>This is v.30</small></p>";
	var fileinfo = document.getElementById('FileData').value;
	var obj = JSON.parse(fileinfo);
	set_kmerDataset('Release49')
	callWS(obj['filename'],obj['nseqs'],obj['reliability'],obj['kmer'],obj['maxGap'],obj['jobID']);
}

function callWS(filename, nseqs, reliability, kmer, maxGap, jobID) {
	var count=0;
	while (count < nseqs) {
		count++;
		var url = baseUrl + "rest_rtmg.cgi/annotate_fasta_file_lite/file/" + filename + "." + count + "/reliability/" + reliability + "/kmer/" + kmer + "/maxgap/" + maxGap + "/jobID/" + jobID + "/level/" + level;
		if (kmerDataset) {url = url + "/kmerDataset/" + kmerDataset};
		sent++;
		document.getElementById('wsCalls').innerHTML = "<p>Data sent: " + sent + " Results received: " +recd + "</p>";
		// xmlreqGET(url);
		xmltableGet(url);
	}
}


/*
 * parse - now all that is passed back from the server is the number of thin
 */

function parse(obj) {
	if (!jobId) {
		var data = JSON.parse(obj);
		jobId = data['result']['jobId'];
	}
	getTable(level);
}

function getTable(level) {
	this.level = level;
	/* document.getElementById('primary').innerHTML = "<b>Getting table with " + level + " levels</b>";
	setTimeout("showWaiting()", 2000);
	var url = baseUrl + "rest_rtmg.cgi/update_table/" + jobId + "/" + level;
	xmltableGet(url); */
	renderTable(level);
}

function parseUrls(obj) {
	var data = JSON.parse(obj);
	responseData = data['result']
	if (!jobId) {
		jobId = responseData['jobId'];
	}
	recd=responseData['received'];
	renderTable(level);
}

function renderTable(level) {
	var url;
	var tableUrl = responseData['tableTxt'];
	if (level == 1) {
		url = responseData['oneLevel'];
		tableUrl = tableUrl['one'];
	}
	else if (level == 2) {
		url = responseData['twoLevel'];
		tableUrl = tableUrl['two'];
	}
	else if (level == 3) {
		url = responseData['threeLevel'];
		tableUrl = tableUrl['three'];
	}
	else {
		url = responseData['tableHtml'];
		tableUrl = tableUrl['raw'];
	}



	if (window.XMLHttpRequest) {
		frames['TableIFrame'].location.href=url;
	}
	else if (window.ActiveXObject) {
		document.all.TableIFrame.src=url;
	}
	clearTimeout(timer);
	document.getElementById('saveBox').innerHTML = "<p><a href='" + tableUrl + "'>Download a text file</a> (e.g. to import to Excel)</p>";
	document.getElementById('primary').innerHTML = "<p><b>Done<b></p>";
	document.getElementById('wsCalls').innerHTML = "<p>Data sent: " + sent + " Results received: " +recd + "</p>";

}

function set_kmerDataset(val) {
	kmerDataset = val;
	document.getElementById('errors').innerHTML = "<p>Using kmer data set " + kmerDataset + "</p>";
}


function showWaiting() {
	if (timerCounter == 1) {
		document.getElementById('primary').innerHTML = "<p><b>Please wait ..</b>";
	}
	else if (timerCounter == 2) {
		document.getElementById('primary').innerHTML = "<p><b>Please wait ....</b>";
	}
	else if (timerCounter == 3) {
		document.getElementById('primary').innerHTML = "<p><b>Please wait ......</b>";
	}
	else {
		document.getElementById('primary').innerHTML = "<p><b>Please wait .........</b>";
		timerCounter=0;
	}


	timerCounter++;
	timer = setTimeout("showWaiting()", 1000);
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
			document.getElementById('errors').innerHTML += "<p>Error getting file at " + pos + " for url " + xmlreqs[pos].xmlhttp.url + "</p>";
		}
		xmlreqs[pos].freed = 1;
	}

}

function xmltableGet(url) {
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
			if (typeof(xmlTableChange) != 'undefined') {
				xmlTableChange(pos);
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

function xmlTableChange(pos) {
	if (typeof(xmlreqs[pos]) != 'undefined' && xmlreqs[pos].freed == 0 && xmlreqs[pos].xmlhttp.readyState == 4) {
		if (xmlreqs[pos].xmlhttp.status == 200 || xmlreqs[pos].xmlhttp.status == 304) {
			parseUrls(xmlreqs[pos].xmlhttp.responseText);
		}
		else {
			document.getElementById('errors').innerHTML = "<p>Error getting file at " + pos + " for url " + xmlreqs[pos].xmlhttp.url + "</p>";
		}
		xmlreqs[pos].freed = 1;
	}

}


