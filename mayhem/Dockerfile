FROM fuzzers/atheris:2.0.7-python3.9

COPY . /html-2-text

# Build Project
WORKDIR /html-2-text
RUN pip install .

# Change Permissions (this will make the fuzzer executable)
RUN chmod +x /html-2-text/mayhem/fuzz-html2text.py