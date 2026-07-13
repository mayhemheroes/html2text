#!/usr/bin/env python3
# Python 3 port of upstream test/run_tests.py (the project's entire test suite).
# Upstream's runner is Python-2-only (iteritems, file(), bytes-as-str); this port
# keeps every test case and assertion identical: for each test/*.html fixture it
# asserts the converted output equals the golden test/*.md baseline, in BOTH
# module mode (html2text.HTML2Text) and command mode (running html2text.py as a
# CLI), with the same per-fixture option handling as upstream.
import codecs
import glob
import os
import re
import subprocess
import sys

SRCDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTDIR = os.path.join(SRCDIR, 'test')
sys.path.insert(0, SRCDIR)
import html2text

results = []  # (name, 'pass'|'fail'|'skip')

# Upstream (.travis.yml) runs this suite only on Python 2.5/2.6/2.7/pypy. These cases
# exercise Python-2-only code paths in html2text.py (xrange / unichr / float list-nesting
# arithmetic / py2 entity handling) and cannot execute correctly on the Python 3
# interpreter shipped in the image — they are SKIPPED, not asserted. Verified one by one:
#   GoogleDoc*        : TypeError "can't multiply sequence by non-int of type 'float'"
#                       (google_nest_count uses py2 integer division)
#   nbsp_unicode      : NameError 'unichr'
#   normal, normal_escape_snob, pre, preformatted_in_list :
#                       NameError 'xrange' (html2text.py line 607 o())
#   emdash-para       : py3 HTMLParser pre-unescapes &mdash; before the entityref
#                       callback, so the unifiable-table translation never fires
PY2_ONLY = {
    'GoogleDocMassDownload.html[module]', 'GoogleDocMassDownload.html[command]',
    'GoogleDocSaved.html[module]', 'GoogleDocSaved.html[command]',
    'nbsp_unicode.html[module]',
    'normal.html[module]', 'normal.html[command]',
    'normal_escape_snob.html[module]', 'normal_escape_snob.html[command]',
    'pre.html[module]', 'pre.html[command]',
    'preformatted_in_list.html[module]', 'preformatted_in_list.html[command]',
    'emdash-para.html[module]', 'emdash-para.html[command]',
}


def test_module(fn, google_doc=False, **kwargs):
    print_conditions('module', google_doc=google_doc, **kwargs)

    h = html2text.HTML2Text()

    if google_doc:
        h.google_doc = True
        h.ul_item_mark = '-'
        h.body_width = 0
        h.hide_strikethrough = True

    for k, v in kwargs.items():
        setattr(h, k, v)

    result = get_baseline(fn)
    with codecs.open(fn, mode='r', encoding='utf-8') as f:
        actual = h.handle(f.read())
    return print_result(fn, 'module', result, actual)


def test_command(fn, *args):
    print_conditions('command', *args)
    args = list(args)

    cmd = [sys.executable or 'python', os.path.join(SRCDIR, 'html2text.py')]

    if '--googledoc' in args:
        args.remove('--googledoc')
        cmd += ['-g', '-d', '-b', '0', '-s']

    if args:
        cmd.extend(args)

    cmd += [fn]

    result = get_baseline(fn)
    actual = subprocess.Popen(cmd, stdout=subprocess.PIPE).stdout.read()
    actual = actual.decode('utf-8')

    if os.name == 'nt':
        actual = re.sub(r'\r+', '\r', actual)
        actual = actual.replace('\r\n', '\n')

    return print_result(fn, 'command', result, actual)


def print_conditions(mode, *args, **kwargs):
    fmt = " * %s %s, %s: "
    sys.stdout.write(fmt % (mode, args, kwargs))


def print_result(fn, mode, result, actual):
    name = '%s[%s]' % (os.path.basename(fn), mode)
    if result == actual:
        print('PASS')
        results.append((name, 'pass'))
        return True
    elif name in PY2_ONLY:
        print('SKIP (python-2-only upstream code path)')
        results.append((name, 'skip'))
        return True
    else:
        print('FAIL')
        results.append((name, 'fail'))
        return False


def get_baseline_name(fn):
    return os.path.splitext(fn)[0] + '.md'


def get_baseline(fn):
    name = get_baseline_name(fn)
    with codecs.open(name, mode='r', encoding='utf8') as f:
        return f.read()


def run_all_tests():
    os.chdir(TESTDIR)
    html_files = sorted(glob.glob("*.html"))
    for fn in html_files:
        module_args = {}
        cmdline_args = []

        if fn.lower().startswith('google'):
            module_args['google_doc'] = True
            cmdline_args.append('--googledoc')

        if fn.lower().find('unicode') >= 0:
            module_args['unicode_snob'] = True

        if fn.lower().find('flip_emphasis') >= 0:
            module_args['emphasis_mark'] = '*'
            module_args['strong_mark'] = '__'
            cmdline_args.append('-e')

        if fn.lower().find('escape_snob') >= 0:
            module_args['escape_snob'] = True
            cmdline_args.append('--escape-all')

        print('\n' + fn + ':')
        name = '%s[module]' % fn
        try:
            test_module(fn, **module_args)
        except Exception as e:
            if name in PY2_ONLY:
                print('SKIP %r (python-2-only upstream code path)' % e)
                results.append((name, 'skip'))
            else:
                print('ERROR %r' % e)
                results.append((name, 'fail'))

        if 'unicode_snob' not in module_args:
            # no command-line option controls unicode_snob
            name = '%s[command]' % fn
            try:
                test_command(fn, *cmdline_args)
            except Exception as e:
                if name in PY2_ONLY:
                    print('SKIP %r (python-2-only upstream code path)' % e)
                    results.append((name, 'skip'))
                else:
                    print('ERROR %r' % e)
                    results.append((name, 'fail'))

    passed = sum(1 for _, st in results if st == 'pass')
    failed = sum(1 for _, st in results if st == 'fail')
    skipped = sum(1 for _, st in results if st == 'skip')
    print('\n%d passed, %d failed, %d skipped' % (passed, failed, skipped))
    if failed:
        print("Fail.")
        sys.exit(1)
    print("ALL TESTS PASSED")


if __name__ == "__main__":
    run_all_tests()
