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

package Bugzilla::Extension::Scrums::Releases;

use lib qw(./extensions/Scrums/lib);

use Bugzilla::Extension::Scrums::Release;
use Bugzilla::Extension::Scrums::Bugorder;
use Bugzilla::FlagType;

use Bugzilla::Util qw(trick_taint);

use XML::Simple;

use strict;
use base qw(Exporter);
use Bugzilla::Error;

# This file can be loaded by your extension via
# "use Bugzilla::Extension::Scruns::Releases". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)
our @EXPORT = qw(
  all_releases
  create_release
  edit_release
  show_release_bugs
  release_bug_order
  handle_release_bug_data
  );

sub all_releases {
    my ($vars) = @_;

    my $cgi            = Bugzilla->cgi;
    my $delete_release = $cgi->param('deleterelease');

    if ($delete_release ne "") {
        if (not Bugzilla->user->in_group('release_managers')) {
            ThrowUserError('auth_failure', { group => "release_managers", action => "delete", object => "release" });
        }
        _delete_release($delete_release);
    }

    $vars->{'releaselist'} = [ Bugzilla::Extension::Scrums::Release->get_all ];
}

sub _delete_release {
    my ($release_id) = @_;

    if (not Bugzilla->user->in_group('release_managers')) {
        ThrowUserError('auth_failure', { group => "release_managers", action => "delete", object => "release" });
    }

    if ($release_id =~ /^([0-9]+)$/) {
        $release_id = $1;    # $data now untainted
        my $release = Bugzilla::Extension::Scrums::Release->new($release_id);
        $release->remove_from_db();
    }
}

sub create_release {
    my ($vars) = @_;

    my $cgi        = Bugzilla->cgi;
    my $release_id = $cgi->param('releaseid');

    if ($release_id ne "") {
        if ($release_id =~ /^([0-9]+)$/) {
            $release_id = $1;    # $data now untainted

            my $release = Bugzilla::Extension::Scrums::Release->new($release_id);

            if ($cgi->param('editrelease') ne "") {
                if (not Bugzilla->user->in_group('release_managers')) {
                    ThrowUserError('auth_failure', { group => "release_managers", action => "edit", object => "release" });
                }
                my $release_name = $cgi->param('releasename');
                my $mr_begin     = $cgi->param('mr_begin');
                my $mr_end       = $cgi->param('mr_end');
                my $algorithm    = $cgi->param('algorithm');
                my $original     = $cgi->param('original');
                my $remaining    = $cgi->param('remaining');
                my $error        = _update_release($release, $release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining);
                if ($error ne "") {
                    $vars->{'error'} = $error;
                }
            }
            elsif ($cgi->param('newflagtype') ne "") {
                my $new_flagtype = $cgi->param('newflagtype');
                _add_flagtype($release, $new_flagtype);
            }
            elsif ($cgi->param('removeflagtype') ne "") {
                my $remove_flagtype = $cgi->param('removeflagtype');
                _remove_flagtype($release, $remove_flagtype);
            }
            _show_existing_release($vars, $release);
        }
        else {
            $vars->{'error'} = "Illegal release id. ";
        }
    }
    else {
        _new_release($vars);
    }
}

sub _show_existing_release {
    my ($vars, $release) = @_;

    $vars->{'addflagtype'} = Bugzilla->cgi->param('addflagtype');

    $vars->{'release'}      = $release;
    $vars->{'flagtypelist'} = $release->flag_types;
    $vars->{'allflagtypes'} = Bugzilla::FlagType::match({ is_active => 1, target_type => 'bug' });
}

sub edit_release {
    my ($vars) = @_;

    if (not Bugzilla->user->in_group('release_managers')) {
        ThrowUserError('auth_failure', { group => "release_managers", action => "edit", object => "release" });
    }

    my $cgi = Bugzilla->cgi;
    $vars->{'editrelease'} = $cgi->param('editrelease');
    $vars->{'releaseid'}   = $cgi->param('releaseid');
    $vars->{'releasename'} = $cgi->param('releasename');
    $vars->{'mr_begin'}    = $cgi->param('mr_begin');
    $vars->{'mr_end'}      = $cgi->param('mr_end');
    $vars->{'algorithm'}   = $cgi->param('algorithm');
    $vars->{'original'}    = $cgi->param('original');
    $vars->{'remaining'}   = $cgi->param('remaining');
}

sub show_release_bugs {
    my ($vars) = @_;

    my $cgi        = Bugzilla->cgi;
    my $release_id = $cgi->param('releaseid');
    my $release    = Bugzilla::Extension::Scrums::Release->new($release_id);
    $vars->{'release'}            = $release;
    $vars->{'scheduled_bugs'}     = $release->scheduled_bugs();
    $vars->{'unprioritised_bugs'} = $release->unprioritised_bugs();
}

# This method is failure because XMLin can not be used without parameter forcearray=> in place
# Using 'forcearray' on the other hand produces different structure of in-memory object.

sub donotuse_release_bug_order {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;

    my $content               = $cgi->param('content');
    my $ordered_bugs_document = XMLin($content);

    my @bug_lists_array = $ordered_bugs_document->{'bug'};
    my $bug_list_ref    = $bug_lists_array[0];
    my @bug_id_array    = keys %{$bug_list_ref};

    for my $bug_id (@bug_id_array) {
        my $child_tag_hash_ref = $bug_list_ref->{$bug_id};
        if (defined $child_tag_hash_ref && ref($child_tag_hash_ref)) {
            my $priority  = $child_tag_hash_ref->{'releasepriority'};
            my $bug_order = Bugzilla::Extension::Scrums::Bugorder->new($bug_id);

            if (defined $bug_order && ref($bug_order)) {
                $bug_order->set_release_order($priority);
                $bug_order->update();
            }
            else {
                $bug_order = Bugzilla::Extension::Scrums::Bugorder->create({ bug_id => $bug_id, rlease => $priority });
            }
        }
        else {
            $vars->{'error'} .= "\nNo child tags where found for bug: " . $bug_id;
        }
    }
}

sub handle_release_bug_data {
    my ($vars) = @_;

    my $cgi    = Bugzilla->cgi;
    my $action = $cgi->param('action');

    if ($action eq 'fetch') {
        my $release_id = $cgi->param('releaseid');
        my $release    = Bugzilla::Extension::Scrums::Release->new($release_id);
        use JSON;
        #$vars->{'header'} = header('application/json');
        $vars->{'json_text'} = to_json([ $release->scheduled_bugs(), $release->unprioritised_bugs() ]);
    }
    elsif ($action eq 'set') {
        my $msg = "set";
        my $release_id = $cgi->param('obj_id');
        my $data    = $cgi->param('data');

        my $json = new JSON::XS;
        if ($data =~ /(.*)/) {
            $data = $1;    # $data now untainted
        }
        my $content = $json->allow_nonref->utf8->relaxed->decode($data);
        my $ordered_list     = $content->{"0"};        
        my $counter = 1;
        for my $bug_id (@{$ordered_list}) {
            _set_bug_release_order($bug_id, $counter);
            $msg = $msg . "bug:" . $bug_id . "," . "order:" . $counter . ";"; # DEBUG
            $counter = $counter + 1;
        }
        my $unprioritised_list     = $content->{"-1"};        
        for my $unprioritised_bug_id (@{$unprioritised_list}) {
            _set_bug_release_order($unprioritised_bug_id, "NULL");
            $msg = $msg . "unprioritised bug:" . $unprioritised_bug_id . ";"; # DEBUG
        }

        $vars->{'json_text'} = to_json([$msg]);
    }
}

sub _set_bug_release_order() {
    my ($bug_id, $order_nr) = @_;

    my $bug_order = Bugzilla::Extension::Scrums::Bugorder->new($bug_id);

    if (defined $bug_order && ref($bug_order)) {
        $bug_order->set_release_order($order_nr);
        $bug_order->update();
    }
    else {
        $bug_order = Bugzilla::Extension::Scrums::Bugorder->create({ bug_id => $bug_id, rlease => $order_nr });
    }
}

# Notice that method XMLin is used parameter forcearray=> in place. Parameter must be used as such.
# Reason is that resulting in-memory object tree, that results from parsing is inconsistent without parameter.
# In situation, when there is only one child tag like one bug for example, parsing result would become different
# from what it becomes in situation where there are several tags.

sub release_bug_order {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;
    #    my $release_id = $cgi->param('releaseid');

    # There was no success in reading request body from XmlHttpRequest. Content
    # is consequently coded into URL. This is not a problem, because URL is not browser URL.
    #    my $body = $cgi->var($CGI::ENTITY_BODY);
    my $content = $cgi->param('content');
    my $ordered_bugs_document = XMLin($content, forcearray => 1);

    my @bug_tag_data_array    = $ordered_bugs_document->{'bug'};
    my $bug_content_array_ref = $bug_tag_data_array[0];            # Array has only one element
    my @bug_content_array     = @{$bug_content_array_ref};

    for my $child_tags_ref (@bug_content_array) {
        my $bug_id           = @{ $child_tags_ref->{'id'} }[0];
        my $release_priority = @{ $child_tags_ref->{'releasepriority'} }[0];

        my $bug_order = Bugzilla::Extension::Scrums::Bugorder->new($bug_id);

        if (defined $bug_order && ref($bug_order)) {
            $bug_order->set_release_order($release_priority);
            $bug_order->update();
        }
        else {
            $bug_order = Bugzilla::Extension::Scrums::Bugorder->create({ bug_id => $bug_id, rlease => $release_priority });
        }
    }
}

sub _new_release {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;

    if (not Bugzilla->user->in_group('release_managers')) {
        ThrowUserError('auth_failure', { group => "release_managers", action => "add", object => "release" });
    }

    my $release_name = $cgi->param('releasename');
    my $mr_begin     = $cgi->param('mr_begin');
    my $mr_end       = $cgi->param('mr_end');
    my $algorithm    = $cgi->param('algorithm');
    my $original     = $cgi->param('original');
    my $remaining    = $cgi->param('remaining');

    my $error = "";
    ($error, $release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining) =
      _sanitize($release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining);

    if ($release_name) {
        my $release = Bugzilla::Extension::Scrums::Release->create({ name => $release_name });

        if ($mr_begin and $mr_end) {
            $release->set_target_milestone_begin($mr_begin);
            $release->set_target_milestone_end($mr_end);
        }
        _show_existing_release($vars, $release);
    }
    else {
        $vars->{'error'} = $error;
    }

    $vars->{'releaseisnew'} = 'true';
}

sub _update_release {
    my ($release, $release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining) = @_;

    my $error = "";

    ($error, $release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining) =
      _sanitize($release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining);

    if ($error eq "") {
        $release->set_name($release_name);
        $release->set_target_milestone_begin($mr_begin);
        $release->set_target_milestone_end($mr_end);
        $release->set_capacity_algorithm($algorithm);
        $release->set_original_capacity($original);
        $release->set_remaining_capacity($remaining);
        $release->update();
    }

    return $error;
}

sub _add_flagtype {
    my ($release, $type_id) = @_;

    if ($type_id =~ /^([0-9]+)$/) {
        $type_id = $1;    # $data now untainted
        $release->set_flag_type($type_id);
    }
}

sub _remove_flagtype {
    my ($release, $type_id) = @_;

    if ($type_id =~ /^([0-9]+)$/) {
        $type_id = $1;    # $data now untainted
        $release->remove_flag_type($type_id);
    }
}

sub _sanitize {
    my ($release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining) = @_;

    my $error = "";
    if ($release_name =~ /^([-\ \w]+)$/) {
        $release_name = $1;    # $data now untainted
    }
    else {
        $error        = "Illegal name. ";
        $release_name = "";
    }

    if ($mr_begin =~ /^\ *([0-9][0-9][0-9][0-9]-[0-9][0-9])\ *$/) {
        $mr_begin = $1;        # $data now untainted
    }
    else {
        $error    = "Illegal beginning of milestore range value.";
        $mr_begin = "";
    }

    if ($mr_end =~ /^\ *([0-9][0-9][0-9][0-9]-[0-9][0-9])\ *$/) {
        $mr_end = $1;          # $data now untainted
    }
    else {
        $error  = "Illegal end of milestore range value." . $mr_end;
        $mr_end = "";
    }

    if ($algorithm =~ /^([-\ \w]*)$/) {
        $algorithm = $1;       # $data now untainted
    }
    else {
        $error     = "Illegal algorithm. ";
        $algorithm = "";
    }

    if ($original =~ /^([0-9]*)$/) {
        $original = $1;        # $data now untainted
    }
    else {
        $error .= "Illegal original capacity value.";
        $original = "";
    }

    if ($remaining =~ /^([0-9]*)$/) {
        $remaining = $1;       # $data now untainted
    }
    else {
        $error .= "Illegal remaining capacity value.";
        $remaining = "";
    }

    return ($error, $release_name, $mr_begin, $mr_end, $algorithm, $original, $remaining);
}

1;
