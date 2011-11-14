# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Scrums Bugzilla Extension.
#
# The Initial Developer of the Original Code is "Nokia corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

package Bugzilla::Extension::Scrums;

use strict;

use constant NAME => 'Scrums';

use constant REQUIRED_MODULES => [
    {
       package => 'libdate-calc-perl',
       module  => 'Date::Calc',
       version => 6.0,
    },

    {
       package => 'libxml-simple-perl',
       module  => 'XML::Simple',
       version => 2.18,
    },

    {
       package => 'libjson-perl',
       module  => 'JSON',
       version => 2.21,
    },

    {
       package => 'libjson-xs-perl',
       module  => 'JSON::XS',
       version => 2.2,
    },
];

use constant OPTIONAL_MODULES => [];

__PACKAGE__->NAME;
