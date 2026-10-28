# Input outside the workflow directory (copied to _EXTERNAL/ in ZIP mode)
rule extra:
    input:
        "../external/extra.txt",
    output:
        "results/extra.txt",
    shell:
        "cp {input} {output}"
