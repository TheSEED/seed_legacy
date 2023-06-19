
function selector() {
	var start = document.getElementById('startswith').value;
	var selector = document.getElementById('subsystem');
	var len = selector.length;
	var newselector={};
	var startlen = start.length;
	for (i=0; i<len; i++) {
		if (selector.options[i].value.slice(0, startlen) == start) {
			newselector[selector.options[i].value]=[selector.options[i].text];
		}
	}
	selector.options.length=0;
	for(index in newselector) {
		selector.options[selector.options.length] = new Option(newselector[index], index);
	}
}


