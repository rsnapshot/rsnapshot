# Developer Notes

This file is intended for developers and packagers of rsnapshot,
not for regular users. If you want to contribute, it's a
good idea to read this document. Although the file is called *contributing*, it
describes the whole release and development process.

## Bug tracker

The bug tracker is hosted on [Github](https://github.com/DrHyde/rsnapshot/issues). Please don't report any issues in the tracker on Sourceforge.

## Source code control

The rsnapshot source code is on [Github](https://github.com/DrHyde/rsnapshot).

Auto-generated files should not get tracked. If you need the configure-script, generate it with `./autogen.sh`. Keep in mind that you have to execute `./autoclean.sh` before you commit.

## Opening Issues

If you have found a bug, open an issue-report on Github. Before you open a report, please search if there are corresponding issues already opened or whether the bug has already been fixed on the `master` branch. Please provide the rsnapshot-version, and describe how to reproduce the bug. It would be great if you could provide also a fix.

## Building rsnapshot

rsnapshot uses the common triple to build software:

    $ ./configure
    $ make
    $ make install

If you checked rsnapshot out of the git-repository, you have to generate the configure-script with:

    $ ./autogen.sh

## Development
The `master` branch should be complete, by which we mean that there should be no half-completed features in it. Any development should be done in a separate branch, each of them containing only a single feature or bugfix.

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

### Fixing Bugs

Create a new branch, prefix it with `issue/` and, if available, the github issue number. (e.g. `issue/35-umount-lvm`).

Add your commits to the branch. They should be logically ordered and clean. Rebase them, if neccessary. Make sure that `make test` passes. Finished? Open a pull-request! The code will get reviewed. If the review passes, a project-member will merge it onto `master` and `release-*` (see below), and will release new bugfix-versions.

## Releases and versions
### release-branches

Releases should be done from branches, named for the release version,
e.g. `release-1-4`. The first release of that version should be tagged `1.4.0`.
Subsequent releases of that version, which should contain no changes other
than bugfixes and security fixes, should also be tagged, e.g. `1.4.1`.

In the end, there should be for every release a branch like `release-X-Y`. The sub-releases should only get tagged on their specific branches.

### release-model in practice
Here is a model presented for release 1.4.0. Make sure, that you start
on the master-branch and have a clean working-directory!

1.  You start branching out of the master-branch
    - `git checkout -b release-1-4`

2.  If there are necessary changes to do before release, make them and commit them now.
    - `git add -A`
    - `git commit -m "Finish Release v1.4.0"`

3.  tag the commit with git and push it to repo
    - `git tag 1.4.0`
    - `git push --tags`

4.  Now generate the configure-file with autogen.sh and make the release-tarball
    - `./autogen.sh`
    - `make dist`

5.  Now upload the tarball to the github-page for the specific version.


### make targets

* *make man*: generate the man page from POD data in rsnapshot
* *make html*: generate a HTML page from POD data in rsnapshot
* *make doc*: man + html
* *make test*: run the testsuite
* *make clean*: clean up the mess from autoconf
* *make dist*: make the release-tarball

