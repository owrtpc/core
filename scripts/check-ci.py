#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Require the latest push CI run for this exact commit; fail closed."""
import json
import re
import sys
import urllib.request


def verify(data, commit):
    runs = [r for r in data.get('workflow_runs', [])
            if r.get('head_sha') == commit and r.get('head_branch') == 'main'
            and r.get('event') == 'push' and r.get('path') == '.github/workflows/ci.yml']
    if not runs:
        raise ValueError('no push CI run found for this commit')
    latest = max(runs, key=lambda r: (r['run_number'], r.get('run_attempt', 1)))
    if latest.get('status') != 'completed' or latest.get('conclusion') != 'success':
        raise ValueError('latest CI run is not successfully completed')
    return latest['html_url']


def main():
    commit = sys.argv[1]
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('invalid source commit')
    url = ('https://api.github.com/repos/owrtpc/core/actions/workflows/ci.yml/runs'
           f'?head_sha={commit}&branch=main&event=push&per_page=100')
    request = urllib.request.Request(url, headers={
        'Accept': 'application/vnd.github+json', 'User-Agent': 'owrtpc-release'})
    with urllib.request.urlopen(request, timeout=30) as response:
        print(verify(json.load(response), commit))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        sys.exit(f'Release blocked: cannot verify successful CI: {error}')
