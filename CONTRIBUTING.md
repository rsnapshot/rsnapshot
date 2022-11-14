# Developer Notes

This file is intended for developers and packagers of rsnapshot,
not for regular users. If you want to contribute, it's a
good idea to read this document. Although the file is called *contributing*, it
describes the whole release and development process.

## Bug tracker

The bug tracker is hosted on [Github](https://github.com/rsnapshot/rsnapshot/issues). Please don't report any issues in the tracker on Sourceforge.

## Source code control

The rsnapshot source code is on [Github](https://github.com/rsnapshot/rsnapshot).

Auto-generated files should not get tracked. If you need the configure-script, generate it with `./autogen.sh`. Keep in mind that you have to execute `./autoclean.sh` before you commit.

## Opening Issues

If you have found a bug, open an issue-report on Github. Before you open a report, please search if there are corresponding issues already opened or whether the bug has already been fixed on the `master` branch. Please provide the rsnapshot-version, and describe how to reproduce the bug. It would be great if you could provide also a fix.

## Building rsnapshot

If you checked rsnapshot out of the git-repository, you have to generate the configure-script with:

    $ ./autogen.sh

rsnapshot uses the common triple to build software:

    $ ./configure
    $ make
    $ make install

## Development

The `master` branch should be complete, by which we mean that there should be no half-completed features in it. Any development should be done in a separate branch, each of them containing only a single feature or bugfix.

![The branch-model in general](./contrib/branchtree.svg?raw=true)

### Coding standards

Changes that do not conform to the coding standard will not be accepted. The current coding standard is primarily encapsulated in the code itself. However briefly:

 * Use tabs not white space.
 * There should be no trailing white space on any lines.
 * The soft line length limited should be 80 characters.

### Adding features

Fork the repository and open a new branch prefixed with `feature/`. Keep the name short and descriptive. Before opening a Pull-Request against the main repository, make sure that:

 * you have written tests, which test the functionality
 * all the tests pass
 * your commits are logically ordered
 * your commits are clean

If it is not the case, please rebase/revise your branch. When you're finished you can create a pull request. Your changes will then be reviewed by a team member, before they can get merged into `master`.

### Documentation

We very much welcome improvements to the documentation. It lives in two places. First, the program itself is
documented in this repository. Second, the website [rsnapshot.org](https://rsnapshot.org) lives in a separate
[Git repository](https://github.com/rsnapshot/rsnapshot.github.io).

### Fixing Bugs

Create a new branch, prefix it with `issue/` and, if available, the github issue number. (e.g. `issue/35-umount-lvm`).

Add your commits to the branch. They should be logically ordered and clean. Rebase them, if neccessary. Make sure that `make test` passes. Finished? Open a pull-request! The code will get reviewed. If the review passes, a project-member will merge it onto `master` and `release-*` (see below), and will release new bugfix-versions.

### Test cases

We encourage you to write a test case for your pull-request. rsnapshot lacks of a proper testsuite, so please write tests whenever you create a Pull-request touching code at the program. We can verify your changes and intentions easier.

 1. Create a directory in the testsuite-folder (`t/`) with the desired test-name. And create in this also a subfolder named `conf`.
 2. Copy the skelleton-file from `t/support/skel/testcase` into your testcase-folder and name it like your folder with the **ending `.t.in`**.
 3. Do the same with the conf-file `t/support/skel/testconf`, but copy it into your conf-folder. Give the file the same name and with the **ending `.conf.in`**.
 4. Write your tests and of course test them.

A few notes on the testsuite:

 - Use the SysWrap-module actively.
 - Any file commited in the testsuite-folder ending with `.conf` or `.t` is commited or named wrong.
 - Let your files always end with `.in` and execute `autogen.sh` before you run your testsuite.
 - Always place your configuration-files into the `conf`-subfolder.
 - If you have got multiple tests to check, which are quite similar, use one test-file, and multiple configuration-files located in your test-folder. (Look at the cmd-post_pre-exec testcase).

## Releases and versions

### release-branches

Releases should be done from branches, named for the release version, e.g. `release-1.4`. The first release of that version should be tagged `1.4.0`. Subsequent releases of that version, which should contain no changes other than bugfixes and security fixes, should also be tagged, e.g. `1.4.1`.

In the end, there should be for every minor release a branch like `release-X.Y`. The sub-releases should only get tagged on their specific branches.

### release-model in practice

Here is a model presented for release 1.4.0. Make sure, that you start on the master-branch and have a clean working-directory!

 1.  You start branching out of the master-branch
    - `git checkout -b release-1-4`

 2.  If there are necessary changes to do before release, make them and commit them now.
    Mind: Any auto-generated script should *not* get tracked. You should only merge the actual changes.
    The configure-scripts are generated later for the release.
    - `git add -A`
    - `git commit -m "Finish Release v1.4.0"`

 3.  tag the commit with git and push it to repo
    - `git tag 1.4.0`
    - `git push --tags`

 4.  Wait for Travis-CI to finish, the fully-built release is then available on the Github-releases page.

    Travis will execute these commands to make a release:
    - `./autogen.sh`
    - `make`
    - `make tar`
    - upload generated file by make tar to Github releases-page

### make targets

 * *make man*: generate the man page from POD data in rsnapshot
 * *make html*: generate a HTML page from POD data in rsnapshot
 * *make doc*: man + html
 * *make test*: run the testsuite
 * *make clean*: clean up the mess from autoconf
 * *make dist*: make the release-tarball
