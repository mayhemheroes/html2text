#!/usr/bin/python3
import atheris
import sys

with atheris.instrument_imports():
    import html2text

@atheris.instrument_func
def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    in_str = fdp.ConsumeString(4096)
    html2text.html2text(in_str)

def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()

if __name__ == "__main__":
    main()