with open(snakemake.output[0], "w") as out:
    for f in snakemake.input:
        out.write(open(f).read())
