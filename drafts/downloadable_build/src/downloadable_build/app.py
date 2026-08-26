PROMPT = 'Build a downloadable sample'

def build_summary() -> str:
    return f"SaNa generated scaffold for: {PROMPT}"

def main() -> None:
    print(build_summary())
