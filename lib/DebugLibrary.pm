#!/usr/bin/perl

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
# The Initial Developer of the Original Code is "Nokia Corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

package Bugzilla::Extension::Scrums::DebugLibrary;

use strict;

use Data::Dumper;
use lib qw(. lib);

use Bugzilla;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint);

use Bugzilla::Extension::Scrums::Sprint;

use base qw(Exporter);

our @EXPORT = qw(
  debug_function
  );

use constant TEAMCOUNT        => 1;
use constant TEAMSIZE         => 5;
use constant SPRINTCOUNT      => 8;
use constant SPRINTLENGTH     => 28;
use constant MAX_STORY_LENGTH => 16;

use vars qw(%data);

sub debug_function($) {
    my ($vars) = @_;

    $vars->{'output'} .= "<p><strong>debug_function</strong><br />";

    my $sprint_id = 13;
    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    $sprint->add_bug_into_sprint(111222, 131174);
    $vars->{'output'} .= "<p>Bug added to sprint><br />";
    return;
}

1;
