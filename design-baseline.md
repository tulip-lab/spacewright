# Workspace System Status and Design Baseline

## 1. Overview

This document records the current baseline design, implementation status, and confirmed architectural decisions for the workspace automation system.

The system has now reached a stable and usable stage. The main design direction is:

- keep internal-display spaces as reusable fixed workstations
- create external-display task spaces only when their core application is actually open
- make mode switching predictable and symmetric
- stop over-optimizing for minor utility-window noise when the layout behavior is already stable

---

## 2. High-Level Architecture

The workspace system is now organized into two major categories.

### 2.1 Internal fixed workspaces

These are long-lived, reusable spaces on the internal display.

Current examples:

- `gtd_chat`
- `gtd_calendar`
- `coding_control`

Design principles:

- reuse existing labeled spaces whenever possible
- create only if the labeled space does not exist
- do not clear labels and recreate repeatedly
- allow these spaces to persist across mode switches
- treat them as stable auxiliary workstations

This design has already proven effective because it resolved the earlier issue of accumulating blank internal-display spaces.

### 2.2 External task workspaces

These are task-oriented spaces on the external display.

Current examples include:

#### GTD
- `gtd_mail_wide / tall`
- `gtd_meeting_wide / tall`
- `gtd_support_wide / tall`
- `gtd_review_wide / tall`

#### Coding
- `coding_editor_wide / tall`

#### Office
- `office_writing_wide / tall`
- `office_slides_wide / tall`

#### Research
- `research_wide / tall`

Design principles:

- reuse existing labeled spaces whenever possible
- create only if the labeled space does not exist
- check whether the core application exists before creating the space
- if the core application is absent, return immediately
- never create an empty labeled space

This is now the most important unified rule across GTD, Coding, Office, and Research.

---

## 3. Core Rule for External Spaces

External task workspaces are now governed by a single rule:

> A task space is only created if its core application is currently open.

The confirmed mapping is as follows.

### 3.1 GTD Mail
Core application:
- `Thunderbird`

Rule:
- if Thunderbird is not open, do not create `gtd_mail_*`

### 3.2 GTD Review
Core application:
- `Preview`

Rule:
- if Preview is not open, do not create `gtd_review_*`

### 3.3 Office Writing
Core application:
- `Microsoft Word`

Rule:
- if Word is not open, do not create `office_writing_*`

### 3.4 Office Slides
Core application:
- `Microsoft PowerPoint`

Rule:
- if PowerPoint is not open, do not create `office_slides_*`

### 3.5 Research
Core application:
- `Zotero`

Rule:
- if Zotero is not open, do not create `research_*`

### 3.6 Coding Editor
Core application:
- `Code` (VS Code)

Rule:
- if VS Code is not open, do not create `coding_editor_*`

This rule is now consistently applied across all external task workspaces.

---

## 4. Internal Workspaces and Their Rules

Internal workspaces are not controlled by a single “must-exist” app in the same way. They are treated as stable auxiliary spaces.

### 4.1 `gtd_chat`
Purpose:
- persistent communication workspace on the internal display

Main apps:
- Keybase
- WeChat
- DingTalk
- Messages
- other chat windows as needed

Rule:
- reuse labeled space
- allow persistence across mode switches
- do not require destruction during normal switching

### 4.2 `gtd_calendar`
Purpose:
- persistent schedule workspace on the internal display

Layout:
- left: `Calendar`
- right: `Reminders`

Rule:
- reuse labeled space
- included by default in both:
  - `gtd_wide_all`
  - `gtd_tall_all`

### 4.3 `coding_control`
Purpose:
- persistent coding support workspace on the internal display

Main apps:
- `Warp`
- `SmartGit`

Rule:
- do not treat SmartGit as a hard creation condition
- process the space if either Warp or SmartGit exists
- if both are absent, return immediately
- reuse labeled space whenever possible

Confirmed layout:

- `Warp` occupies the upper `2/3` of the display
- `SmartGit` uses absolute position and size

Confirmed placement logic:

```fish
if test -n "$warp"
    yabai -m window $warp --grid 3:1:0:0:1:2
end
if test -n "$smartgit"
    yabai -m window $smartgit --move abs:300:60
    yabai -m window $smartgit --resize abs:1200:1040
end