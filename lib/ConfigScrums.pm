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
# The Initial Developer of the Original Code is "Nokia Corporation".
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>
#   Pami Ketolainen <pami.ketolainen@gmail.com>

package Bugzilla::Extension::Scrums::ConfigScrums;
use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Field;

sub get_param_list {
    my ($class) = @_;

    my @legal_severities = @{get_legal_field_values('bug_severity')};

    my @param_list = (
        {
            name    => 'scrums_use_points',
            desc    => 'Display estimated, remaining and actual time as points '.
                        'instead of hours',
            type    => 'b',
            default => 0
        },
        {
            name    => 'scrums_bug_comment_editable_item_types',
            desc    => 'List of severities of those bugs, that are possible '.
                        'to edit. Item comment is editable description.',
            type    => 'm',
            choices => \@legal_severities,
            default => [ $legal_severities[-1] ]
        },
        {
            name    => 'scrums_precondition_enabled_severity',
            desc    => 'List of severities of those bugs, that are required '.
                        'to have estimated time and worked time when closing bug.',
            type    => 'm',
            choices => \@legal_severities,
            default => [ $legal_severities[-1] ]
        },
        {
            name    => 'scrums_default_sprint_days',
            desc    => 'Default length of a sprint for JS datepicker.',
            type    => 't',
            default => '7'
        },
    );
    return @param_list;
}

1;
