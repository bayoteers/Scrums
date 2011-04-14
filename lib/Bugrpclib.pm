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

package Bugzilla::Extension::Scrums::Bugrpclib;

use lib qw(./extensions/Scrums/lib);

use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint);

use JSON::XS;

use strict;
use base qw(Exporter);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::Scruns::Releases". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)
our @EXPORT = qw(
  update_bug_fields_from_json
  );
#
# Important!
# Data needs to be in exact format:
#
#  { "method": "Bug.update", "params": {"ids" : [216089], "estimated_time," : 0.8}, "id" : 0 }
#

sub update_bug_fields_from_json {
    my ($vars) = @_;

    my $cgi    = Bugzilla->cgi;
    my $action = $cgi->param('action'); # Future use
    my $data       = $cgi->param('data');

    my $json = new JSON::XS;
    if ($data =~ /(.*)/) {
        $data = $1;    # $data now untainted
    }
    my $content = $json->allow_nonref->utf8->relaxed->decode($data);

#    my %all_properties_from_rpc = %{$content};

#    my $params = $content->{params};
#    my $ids = $params->{ids};
#    my $bug_id = @{$ids}[0];
#    return $bug_id;

    my ($params, $ids, $bug_id, $field_name, $field_value);
    my $params = $content->{params};
    my @param_keys = keys %{$params};
    for my $key (@param_keys) {
        if($key eq "ids") {
            $ids = $params->{$key};
            $bug_id = @{$ids}[0];                    
        }
        else {
            $field_name = $key;
            $field_value = $params->{$key};
        }
    }
    
    my $bug = Bugzilla::Bug->new($bug_id);
    my $old_value;
    if($field_name eq 'estimated_time') {
        $bug->set_estimated_time($field_value);
        $bug->update();
    }
    elsif($field_name eq 'remaining_time') {
        $bug->set_remaining_time($field_value);
        $bug->update();
    }
    elsif($field_name eq 'assigned_to') {
        if(Bugzilla::User::login_to_id($field_value))
        {
            # Login name is ok    
            $bug->set_assigned_to($field_value);
            $bug->update();
        }
        else
        {
            $vars->{errors} = "login_name: " . $field_value. " is not known to Bugzilla";
        }
    }
    else
    {
        $vars->{errors} = "Not able to save column " . $field_name;
    }

#column == 'bug_severity' ||
#	column == 'priority' ||
#	column == 'bug_status' ||
#	column == 'assigned_to' ||
#	column == 'estimated_time' ||
#	column == 'actual_time' ||
#	column == 'remaining_time' %]
}

1;
