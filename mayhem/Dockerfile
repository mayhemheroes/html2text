FROM fuzzers/atheris:2.0.7-python3.9

COPY . /thefuzz

# Build Project
WORKDIR /html-2-text
RUN pip install .

# Change Permissions
RUN chmod +x /html-2-text/mayhem/fuzz.py