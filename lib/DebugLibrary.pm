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
  debug_function1
  debug_function2
  debug_function3
  debug_function4
  debug_set2_func1
  );

sub debug_function1($) {
    my ($vars) = @_;

    $vars->{'output'} .= "<p><strong>debug_function1</strong><br />";

    my $sprint_id = 13;
    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    my $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    $vars->{'output'} .= "\$added_bug_id: " . "111222" . " \$insert_after_bug_id: " . "131174" . "<br />";
    $sprint->add_bug_into_sprint(111222, 131174, $vars);
    $vars->{'output'} .= "<p>Bug added to sprint><br />";

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    return;
}

sub debug_function2($) {
    my ($vars) = @_;

    $vars->{'output'} .= "<p><strong>debug_function2</strong><br />";

    my $sprint_id = 13;
    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    my $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    $vars->{'output'} .= "\$removed_bug_id: " . "111222" . "<br />";
    $sprint->remove_bug_from_sprint(111222, $vars);
    $vars->{'output'} .= "<p>Bug removed from sprint><br />";

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    return;
}

sub debug_function3($) {
    my ($vars) = @_;

    $vars->{'output'} .= "<p><strong>debug_function3</strong><br />";

    my $sprint_id = 13;
    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    my $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    $vars->{'output'} .= "\$added_bug_id: " . "111222" . " \$insert_after_bug_id: " . "131174" . "<br />";
    $sprint->add_bug_into_sprint(111222, 131174, $vars);
    $vars->{'output'} .= "<p>Bug added to sprint><br />";

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    $vars->{'output'} .= "\$added_bug_id: " . "111222" . " \$insert_after_bug_id: " . "214952" . "<br />";
    $sprint->add_bug_into_sprint(111222, 214952, $vars);
    $vars->{'output'} .= "<p>Bug added to sprint><br />";

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    return;
}

sub debug_function4($) {
    my ($vars) = @_;

    $vars->{'output'} .= "<p><strong>debug_function4</strong><br />";

    my $sprint_id = 13;
    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    my $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    $vars->{'output'} .= "\$added_bug_id: " . "111222" . " \$insert_after_bug_id: " . "135537" . "<br />";
    $sprint->add_bug_into_sprint(111222, 135537, $vars);
    $vars->{'output'} .= "<p>Bug added to sprint><br />";

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    return;
}

#----------------------------------------------------------------------------------------

sub debug_set2_func1($) {
    my ($vars) = @_;

    $vars->{'output'} .= "<p><strong>debug_set2_func1</strong><br />";

    my $sprint_id = 182; # Team 'Backlog test' sprint 'testi 3'
    my $sprint    = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    my $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    $vars->{'output'} .= "\$added_bug_id: " . "215716" . " \$insert_after_bug_id: " . "[no bug]" . "<br />";
    $sprint->add_bug_into_sprint(215716, undef, $vars);
    $vars->{'output'} .= "<p>Bug added to sprint><br />";

    $vars->{'output'} .= "<br />";
    $vars->{'output'} .= "Tested sprint: " . $sprint->name() . "<br />";
    $sprint_bug_list = $sprint->get_items();
    for my $bug_row (@{$sprint_bug_list}) {
        $vars->{'output'} .= "bug no:" . @$bug_row[8] . " id:" . @$bug_row[0] . "<br />";
    }

    return;
}

1;
