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
      static_content = elem.html();
      elem.html(create_select_html());
  }

  function create_bug() {
      var elem = $("#createbug");
      var selected = product_list[elem.find("select").val()];
      elem.find("[name='product']").val(selected[0]);
      elem.find("[name='component']").val(selected[1]);
      elem.find("form").submit();
      cancel();
  }

  function cancel() {
      $("#createbug").html(static_content);
  }

  function create_select_html() {

      var html = '<table>';
      html +=      '<tr><td><h3>Enter bug</h3></td></tr>';
      html +=      '<tr>';
      html +=        '<td><b>Product:</b></td>';
      html +=        '<td>';
      html +=            '<select id="createbug-product">';
      for(i = 0; i < product_list.length; i++) {
          html +=          '<option value="' + i + '">';
          html += product_list[i][2];
          html +=          '</option>';
      }
      html +=            '</select>';
      html +=        '</td>';
      html +=      '</tr>';
      html +=      '<tr><td colspan="2">&nbsp;</td></tr>';
      html +=      '<tr><td>&nbsp;</td>';
      html +=        '<td>';
      html +=          '<form action="enter_bug.cgi" method="post" target="_BLANC">';
      html +=            '<input name="product" type="hidden" value=""/>';
      html +=            '<input name="component" type="hidden" value=""/>';
      html +=            '<input type="button" value="cancel" onclick="cancel();"/>&nbsp;';
      html +=            '<input type="button" value="start" onclick="create_bug();"/>';
      html +=          '</form>';
      html +=        '</td>';
      html +=      '</tr>';
      html +=    '</table>';
      return html;
  }

