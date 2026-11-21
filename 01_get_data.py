"""
01_get_data.py

Build the filtered 2022 HMDA Loan/Application Register (LAR) file that every
experiment samples from.

Steps   1. download the raw LAR file from the CFPB/FFIEC (880 MB) unless it is
           already in raw_data/, and check its SHA-256
        2. filter it and write input_data/2022_public_lar_csv_filtered.zip
        3. check that the output matches the file used in the paper (SHA-256)

Source: the 2022 snapshot national loan-level dataset published by the CFPB/FFIEC,
https://ffiec.cfpb.gov/data-publication/snapshot-national-loan-level-dataset/2022

Sample restrictions (Section 3.3 and Appendix Table A1 of the paper):
conventional, home-purchase, first-lien, 30-year loans for a principal residence
on a site-built single-unit property; no balloon payments, negative amortization,
interest-only payments, reverse mortgages, or business/commercial purpose; and
the application was either originated or denied.

The output is also posted as a release asset on the GitHub repository, so most
users can download it there and skip this script. Running this script reproduces
that file: the CSV inside the zip is byte-for-byte identical to the release copy
(the zip container itself differs only in its timestamp).

Usage:  python 01_get_data.py
Memory: the filter holds ~2.4m rows x 99 columns of text in memory (~12 GB peak).
"""

import csv
import hashlib
import io
import os
import urllib.request
import zipfile

import numpy as np
import pandas as pd
from tqdm import tqdm

RAW_URL = 'https://files.ffiec.cfpb.gov/static-data/snapshot/2022/2022_public_lar_csv.zip'
RAW_ZIP = 'raw_data/2022_public_lar_csv.zip'
RAW_CSV = '2022_public_lar_csv.csv'

OUT_ZIP = 'input_data/2022_public_lar_csv_filtered.zip'
OUT_CSV = '2022_public_lar_csv_filtered.csv'

# SHA-256 of the raw download (as of November 2026) and of the CSV inside the
# output zip used in the paper
RAW_SHA256 = 'df7ad5b544fe8dc7ca05de58a1975fd8970b829136f1538cea83882773e759d4'
OUT_CSV_SHA256 = 'b04654d9dd6db23f318a820955b57234305aa1114d659cea2e89458e51c3d6f6'

# Each column must parse as an integer in the allowed set. Cells that do not parse
# as integers (e.g., "Exempt") are not filtered here; loan_term and total_units
# are the only filter columns with such values and are cleaned up after loading.
FILTERS = {
    'loan_type':                      [1],     # conventional
    'loan_purpose':                   [1],     # home purchase
    'lien_status':                    [1],     # first lien
    'balloon_payment':                [2],     # no balloon payment
    'reverse_mortgage':               [2],     # not a reverse mortgage
    'business_or_commercial_purpose': [2],     # not business/commercial
    'negative_amortization':          [2],     # no negative amortization
    'interest_only_payment':          [2],     # no interest-only payments
    'construction_method':            [1],     # site-built
    'occupancy_type':                 [1],     # principal residence
    'action_taken':                   [1, 3],  # originated or denied
    'loan_term':                      [360],   # 30 years
    'total_units':                    [1],     # single unit
}

FLOAT_COLS = ['rate_spread', 'interest_rate', 'prepayment_penalty_term', 'intro_rate_period',
              'property_value', 'total_loan_costs', 'total_points_and_fees',
              'origination_charges', 'discount_points', 'lender_credits', 'income',
              'combined_loan_to_value_ratio']

# HMDA reports DTI as a percent from 36-49 and in buckets outside that range.
# debt_to_income_ratio2 is a numeric version; the analysis uses its own recode of
# the string variable (see 03_analysis.do).
DTI_MAP = {'<20%': 0.1, '20%-<30%': 0.25, '30%-<36%': 0.32, '36': 0.36,
           '37': 0.37, '38': 0.38, '39': 0.39, '40': 0.4, '41': 0.41,
           '42': 0.42, '43': 0.43, '44': 0.44, '45': 0.45, '46': 0.46,
           '47': 0.47, '48': 0.48, '49': 0.49, '50%-60%': 0.55, '>60%': 0.65}


def sha256(fh):
    h = hashlib.sha256()
    for block in iter(lambda: fh.read(1 << 24), b''):
        h.update(block)
    return h.hexdigest()


def download_raw():
    if not os.path.exists(RAW_ZIP):
        os.makedirs(os.path.dirname(RAW_ZIP), exist_ok=True)
        print(f'Downloading {RAW_URL} (~880 MB)')
        urllib.request.urlretrieve(RAW_URL, RAW_ZIP)
    with open(RAW_ZIP, 'rb') as fh:
        ok = sha256(fh) == RAW_SHA256
    print(f'{RAW_ZIP}: ' + ('SHA-256 matches the download verified to reproduce the paper' if ok else
          'WARNING: SHA-256 differs from the verified download (has the CFPB updated the file?)'))


def verify_output():
    with zipfile.ZipFile(OUT_ZIP) as z, z.open(OUT_CSV) as fh:
        ok = sha256(fh) == OUT_CSV_SHA256
    print(f'{OUT_ZIP}: ' + ('identical to the file used in the paper' if ok else
          'WARNING: differs from the file used in the paper'))


def keep_row(row, col_index):
    for col, allowed in FILTERS.items():
        try:
            if int(row[col_index[col]]) not in allowed:
                return False
        except ValueError:
            pass
    return True


def load_filtered():
    with zipfile.ZipFile(RAW_ZIP) as z, z.open(RAW_CSV) as fh:
        reader = csv.reader(io.TextIOWrapper(fh, encoding='utf-8'))
        header = next(reader)
        col_index = {c: header.index(c) for c in FILTERS}
        rows = [row for row in tqdm(reader, desc='Filtering LAR', unit=' rows')
                if keep_row(row, col_index)]
    df = pd.DataFrame(rows, columns=header)
    del rows

    # "Exempt" loan_term / total_units values survive the row filter; drop them.
    # The index (row position before this step) becomes loan_id below, so this
    # must happen after the DataFrame is built.
    return df.query('loan_term == "360" & total_units == "1"')


def clean(df):
    # integer-like text columns become ints; anything else stays as text
    for c in df.columns:
        try:
            df[c] = df[c].astype('int')
        except (ValueError, TypeError):
            pass

    df = df.filter(regex='^(?!derived)')   # drop HMDA's derived_* columns

    for c in FLOAT_COLS:
        df[c] = df[c].replace(['Exempt', 'NA', 'nan', ''], np.nan).astype(float)

    df['debt_to_income_ratio2'] = df['debt_to_income_ratio'].map(DTI_MAP)
    df['debt_to_income_ratio'] = df['debt_to_income_ratio'].apply(lambda x: x if '%' in x else x + '%')

    # loan_id = row position in the filtered file (before the loan_term/total_units cleanup)
    df = df.reset_index().rename(columns={'index': 'loan_id'})
    return df


def main():
    download_raw()
    df = clean(load_filtered())
    os.makedirs(os.path.dirname(OUT_ZIP), exist_ok=True)
    # lineterminator pinned to CRLF so the output matches the original Windows build on any OS
    df.to_csv(OUT_ZIP, index=False, lineterminator='\r\n',
              compression=dict(method='zip', archive_name=OUT_CSV))
    print(f'Wrote {OUT_ZIP}: {len(df):,} rows x {df.shape[1]} columns')
    verify_output()


if __name__ == '__main__':
    main()
