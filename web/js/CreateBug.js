/**
  * The contents of this file are subject to the Mozilla Public
  * License Version 1.1 (the "License"); you may not use this file
  * except in compliance with the License. You may obtain a copy of
  * the License at http://www.mozilla.org/MPL/
  *
  * Software distributed under the License is distributed on an "AS
  * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
  * implied. See the License for the specific language governing
  * rights and limitations under the License.
  *
  * The Original Code is the Scrums Bugzilla Extension.
  *
  * The Initial Developer of the Original Code is "Nokia Corporation"
  * Portions created by the Initial Developer are Copyright (C) 2011 the
  * Initial Developer. All Rights Reserved.
  *
  * Contributor(s):
  *   Visa Korhonen <visa.korhonen@symbio.com>
  */

  var static_content = "";

  function select_component() {
      var elem = $("#createbug");
      var new_content = create_select_html();
      static_content = elem[0].innerHTML;
      elem[0].innerHTML = new_content;
  }

  function cancel() {
      var elem = $("#createbug");
      elem[0].innerHTML = static_content;
  }

  function create_select_html() {
      var html = '<form action="enter_bug.cgi" method="post" target="_BLANC">';
      html +=    '<table>';
      html +=      '<tr>';
      html +=        '<td>&nbsp;';
      html +=        '</td>';
      html +=        '<td><h3>Enter bug</h3>';
      html +=        '</td>';
      html +=      '</tr>';
      html +=      '<tr>';
      html +=        '<td>';
      html +=          '<b>Product:</b>';
      html +=        '</td>';
      html +=        '<td>';
      html +=            '<select name="product">';
      for(i = 0; i < product_list.length; i++) {
          html +=          '<option value="';
          html += product_list[i][0] + '">';
          html += product_list[i][1];
          html +=          '</option>';
      }
      html +=            '</select>';
      html +=        '</td>';
      html +=      '</tr>';
      html +=      '<tr>';
      html +=        '<td colspan="2">&nbsp;';
      html +=        '</td>';
      html +=      '</tr>';
      html +=      '<tr>';
      html +=        '<td>&nbsp;';
      html +=        '</td>';
      html +=        '<td>';
      html +=          '<input type="button" value="cancel" onclick="cancel();"/>&nbsp;';
      html +=          '<input type="submit" value="start"/>';
      html +=        '</td>';
      html +=      '</tr>';
      html +=    '</table>';
      html += '</form>';
      return html;
  }

