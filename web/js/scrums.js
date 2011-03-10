/*
 * Contributor(s):
 *   Visa Korhonen <visa.korhonen@symbio.com>
 */
var reqXML;
saveResponse = function() {
    if (reqXML.readyState == 4) {
        if (reqXML.status == 200) {
            var strText = reqXML.responseText;
            alert("Save Done.\n" + strText);
        } else {
            alert("There was a problem saving the XML data:\n" + reqXML.statusText);
        }
    }
};
saveReleaseOrderData = function() {
    alert('saveReleaseOrderData');
    //    hide_visibility('save_footer');
    if (window.XMLHttpRequest) {
        reqXML = new XMLHttpRequest();
    } else if (window.ActiveXObject) {
        reqXML = new ActiveXObject("Microsoft.XMLHTTP");
    }
    if (reqXML) {
        var URL = "./page.cgi?id=scrums/release_ajax.html";
        // Start creating the XML
        var xmlBody = "<bug_list>";
        var box1 = document.getElementById("tble1");
        var prioritized_tr_elements = box1.getElementsByClassName("draggable_item");
        for (var j = 0; j < prioritized_tr_elements.length; j++) {
            // get the bug_id
            var anchor_element = prioritized_tr_elements[j].getElementsByTagName("a");
            var bug_id = anchor_element[0].innerHTML; // this is the bug id
            var tempXML = "<bug>";
            tempXML += "<id>" + bug_id + "</id>";
            tempXML += "<releasepriority>" + (j + 1) + "</releasepriority>";
            tempXML += "</bug>";
            xmlBody += tempXML;
        }
        // Will continue with unprioritised bugs. These bugs have releasepriority empty.
        var box1 = document.getElementById("tble2");
        var prioritized_tr_elements = box1.getElementsByClassName("draggable_item");
        for (var j = 0; j < prioritized_tr_elements.length; j++) {
            // get the bug_id
            var anchor_element = prioritized_tr_elements[j].getElementsByTagName("a");
            var bug_id = anchor_element[0].innerHTML; // this is the bug id
            var tempXML = "<bug>";
            tempXML += "<id>" + bug_id + "</id>";
            tempXML += "<releasepriority></releasepriority>";
            tempXML += "</bug>";
            xmlBody += tempXML;
        }
        xmlBody += "</bug_list>";
        // Send the request
        URL = URL + "&content=<?xml version='1.0' encoding='UTF-8'?>" + xmlBody;
        reqXML.open("POST", URL, true);
        reqXML.onreadystatechange = saveResponse;
        reqXML.setRequestHeader("Content-Type", "text/xml");
        reqXML.send();
    } else {
        alert("Your browser does not support Ajax");
    }
};
saveTeamOrderData = function() {
    alert('saveTeamOrderData');
    var sprintno = document.getElementById("sprintno");
    var count = sprintno.value;
    alert('Number of sprints: ' + count);
    //    hide_visibility('save_footer');
    if (window.XMLHttpRequest) {
        reqXML = new XMLHttpRequest();
    } else if (window.ActiveXObject) {
        reqXML = new ActiveXObject("Microsoft.XMLHTTP");
    }
    if (reqXML) {
        var URL = "./page.cgi?id=scrums/release_ajax.html&action=orderteambugs";
/*
        // Start creating the XML
        var xmlBody = "<bug_list>";
	var box1 = document.getElementById("tble1");
	var prioritized_tr_elements = box1.getElementsByClassName("draggable_item");
        for ( var j=0; j < prioritized_tr_elements.length; j++ ) {
             // get the bug_id
	     var anchor_element = prioritized_tr_elements[j].getElementsByTagName("a");
             var bug_id = anchor_element[0].innerHTML; // this is the bug id
             var tempXML = "<bug>";
             tempXML += "<id>" + bug_id + "</id>";
             tempXML += "<releasepriority>" + (j+1) + "</releasepriority>";
             tempXML += "</bug>";
             xmlBody += tempXML;
        }
	// Will continue with unprioritised bugs. These bugs have releasepriority empty.
	var box1 = document.getElementById("tble2");
	var prioritized_tr_elements = box1.getElementsByClassName("draggable_item");
        for ( var j=0; j < prioritized_tr_elements.length; j++ ) {
             // get the bug_id
	     var anchor_element = prioritized_tr_elements[j].getElementsByTagName("a");
             var bug_id = anchor_element[0].innerHTML; // this is the bug id
             var tempXML = "<bug>";
             tempXML += "<id>" + bug_id + "</id>";
             tempXML += "<releasepriority></releasepriority>";
             tempXML += "</bug>";
             xmlBody += tempXML;
        }
        xmlBody += "</bug_list>";
        // Send the request
	URL = URL + "&content=<?xml version='1.0' encoding='UTF-8'?>" + xmlBody;
*/
        reqXML.open("POST", URL, true);
        reqXML.onreadystatechange = saveResponse;
        reqXML.setRequestHeader("Content-Type", "text/xml");
        reqXML.send();
    } else {
        alert("Your browser does not support Ajax");
    }
};
