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
# The Original Code is the Bugzilla Example Plugin.
#
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by Canonical Ltd. are Copyright (C) 2008
# Canonical Ltd. All Rights Reserved.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Bradley Baetz <bbaetz@acm.org>
#                 Jari Savolainen <ext-jari.a.savolainen@nokia.com>

package Bugzilla::Extension::Scrums::ConfigScrums;
use strict;
use warnings;

use Bugzilla::Config::Common;

sub get_param_list {
    my ($class) = @_;

    my @param_list = (
                      {
                        name    => 'bug_list_editable_fields',
                        desc    => 'Those fields in bug, that are editable in bug list directly',
                        type    => 'm',
                        choices => [ 'bug_severity', 'priority', 'assigned_to', 'estimated_time', 'remaining_time' ],
                        default => ['estimated_time']
                      }
                     );
    return @param_list;
}

1;
