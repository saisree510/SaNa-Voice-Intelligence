PROMPT = 'Build the second draft'

def build_summary() -> str:
    return f"SaNa generated scaffold for: {PROMPT}"

def main() -> None:
    print(build_summary())
