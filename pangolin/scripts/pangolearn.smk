#!/usr/bin/env python

import csv
from Bio import SeqIO
import os
import pangofunks as pfunk

##### Configuration #####

if config.get("trained_model"):
    config["trained_model"] = os.path.join(workflow.current_basedir,'..', config["trained_model"])

if config.get("header_file"):
    config["header_file"] = os.path.join(workflow.current_basedir,'..', config["header_file"])

##### Target rules #####

if config.get("lineages_csv"):
    print("Going to run the global report summary")
else:
    config["lineages_csv"]=""


if config["lineages_csv"] != "":
    rule all:
        input:
            config["outfile"],
            os.path.join(config["outdir"],"global_lineage_information.csv")
else:
    rule all:
        input:
            config["outfile"]

rule minimap2_check_distance:
    input:
        fasta = config["query_fasta"],
        reference = config["reference_fasta"]
    output:
        paf = os.path.join(config["tempdir"],"reference_mapped.paf")
    log:
        os.path.join(config["tempdir"], "logs/minimap2_check.log")
    shell:
        """
        minimap2 -x asm5 -t {workflow.cores} {input.reference:q} {input.fasta:q} -o {output.paf:q} &> {log}
        """

rule parse_paf:
    input:
        paf = rules.minimap2_check_distance.output.paf,
        fasta = config["query_fasta"],
    output:
        fasta = os.path.join(config["tempdir"], "mappable.fasta"),
        mapfail = os.path.join(config["tempdir"],"mapfail.csv")
    run:
        mapped = []
        with open(input.paf, "r") as f:
            for l in f:
                tokens = l.rstrip("\n").split('\t')
                mapped.append(tokens[0])
        unmapped = open(output.mapfail, "w")
        with open(output.fasta, 'w') as fw:
            for record in SeqIO.parse(input.fasta,"fasta"):
                if record.id in mapped:
                    fw.write(f">{record.description}\n{record.seq}\n")
                else:
                    unmapped.write(f"{record.id},failed to map\n")
                    
rule align_to_reference:
    input:
        fasta = rules.parse_paf.output.fasta,
        reference = config["reference_fasta"]
    params:
        trim_start = 265,
        trim_end = 29674
    output:
        fasta = os.path.join(config["aligndir"],"sequences.aln.fasta")
    log:
        os.path.join(config["outdir"], "logs/minimap2_sam.log")
    shell:
        """
        minimap2 -a -x asm5 -t {workflow.cores} {input.reference:q} {input.fasta:q} | \
        gofasta sam toMultiAlign \
            --reference {input.reference:q} \
            --trimstart {params.trim_start} \
            --trimend {params.trim_end} \
            --pad > {output.fasta:q}
        """

rule pangolearn:
    input:
        fasta = rules.align_to_reference.output.fasta,
        model = config["trained_model"],
        header = config["header_file"],
        reference = config["reference_fasta"]
    output:
        os.path.join(config["tempdir"],"lineage_report.pass_qc.csv")
    shell:
        # should output a csv file with no headers but with columns similar to:
        # "taxon,lineage,SH-alrt,UFbootstrap"
        """
        pangolearn.py --header-file {input.header:q} --model-file {input.model:q} --reference-file {input.reference:q} --fasta {input.fasta:q} -o {output[0]:q}
        """

rule add_failed_seqs:
    input:
        qcpass= os.path.join(config["tempdir"],"lineage_report.pass_qc.csv"),
        qcfail= config["qc_fail"],
        mapfail = rules.parse_paf.output.mapfail
    params:
        version = config["pangoLEARN_version"]
    output:
        csv= os.path.join(config["tempdir"],"pangolearn_assignments.csv")
    run:
        fw = open(output[0],"w")
        fw.write("taxon,lineage,probability,pangoLEARN_version,status,note\n")

        with open(input.qcpass, "r") as f:
            for l in f:
                l=l.rstrip('\n')
                name,lineage,support = l.split(",")
                support = round(float(support), 2)
                fw.write(f"{name},{lineage},{support},{params.version},passed_qc,\n")

        for record in SeqIO.parse(input.qcfail,"fasta"):
            desc_list = record.description.split(" ")
            note = ""
            for i in desc_list:
                if i.startswith("fail="):
                    note = i.lstrip("fail=")
            # needs to mirror the structure of the output from pangolearn
            fw.write(f"{record.id},None,0,{params.version},fail,{note}\n")
        
        with open(input.mapfail,"r") as f:
            for l in f:
                l = l.rstrip("\n")
                name,fail = l.split(",")
                fw.write(f"{name},None,0,{params.version},fail,{fail}\n")

        fw.close()

rule type_variants_b117:
    input:
        fasta = rules.align_to_reference.output.fasta,
        variants = config["b117_variants"],
        reference = config["reference_fasta"]
    output:
        variants = os.path.join(config["tempdir"],"variants_b117.csv")
    shell:
        """
        type_variants.py \
        --fasta-in {input.fasta:q} \
        --variants-config {input.variants:q} \
        --reference {input.reference:q} \
        --variants-out {output.variants:q} \
        --append-genotypes
        """

rule type_variants_b1351:
    input:
        fasta = rules.align_to_reference.output.fasta,
        variants = config["b1351_variants"],
        reference = config["reference_fasta"]
    output:
        variants = os.path.join(config["tempdir"],"variants_b1351.csv")
    shell:
        """
        type_variants.py \
        --fasta-in {input.fasta:q} \
        --variants-config {input.variants:q} \
        --reference {input.reference:q} \
        --variants-out {output.variants:q} \
        --append-genotypes
        """

rule type_variants_p2:
    input:
        fasta = rules.align_to_reference.output.fasta,
        variants = config["p2_variants"],
        reference = config["reference_fasta"]
    output:
        variants = os.path.join(config["tempdir"],"variants_p2.csv")
    shell:
        """
        type_variants.py \
        --fasta-in {input.fasta:q} \
        --variants-config {input.variants:q} \
        --reference {input.reference:q} \
        --variants-out {output.variants:q} \
        --append-genotypes
        """


rule type_variants_p1:
    input:
        fasta = rules.align_to_reference.output.fasta,
        variants = config["p1_variants"],
        reference = config["reference_fasta"]
    output:
        variants = os.path.join(config["tempdir"],"variants_p1.csv")
    shell:
        """
        type_variants.py \
        --fasta-in {input.fasta:q} \
        --variants-config {input.variants:q} \
        --reference {input.reference:q} \
        --variants-out {output.variants:q} \
        --append-genotypes
        """

rule type_variants_p3:
    input:
        fasta = rules.align_to_reference.output.fasta,
        variants = config["p3_variants"],
        reference = config["reference_fasta"]
    output:
        variants = os.path.join(config["tempdir"],"variants_p3.csv")
    shell:
        """
        type_variants.py \
        --fasta-in {input.fasta:q} \
        --variants-config {input.variants:q} \
        --reference {input.reference:q} \
        --variants-out {output.variants:q} \
        --append-genotypes
        """


rule type_variants_b12142:
    input:
        fasta = rules.align_to_reference.output.fasta,
        variants = config["b12142_variants"],
        reference = config["reference_fasta"]
    output:
        variants = os.path.join(config["tempdir"],"variants_b12142.csv")
    shell:
        """
        type_variants.py \
        --fasta-in {input.fasta:q} \
        --variants-config {input.variants:q} \
        --reference {input.reference:q} \
        --variants-out {output.variants:q} \
        --append-genotypes
        """


rule overwrite:
    input:
        csv = os.path.join(config["tempdir"],"pangolearn_assignments.csv"),
        b117_variants = rules.type_variants_b117.output.variants,
        b1351_variants = rules.type_variants_b1351.output.variants,
        p3_variants = rules.type_variants_p3.output.variants,
        p2_variants = rules.type_variants_p2.output.variants,
        p1_variants = rules.type_variants_p1.output.variants,
        b12142_variants = rules.type_variants_b12142.output.variants
    output:
        csv = config["outfile"]
    run:
        b117 = {}
        with open(input.b117_variants, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row["alt_count"]) > 4 and int(row["ref_count"])<6:
                    b117[row["query"]] = row["alt_count"]
        b1351 = {}
        with open(input.b1351_variants, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row["alt_count"]) > 4 and int(row["ref_count"])<2:
                    b1351[row["query"]] = row["alt_count"]
        p1 = {}
        with open(input.p1_variants, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row["alt_count"]) > 10:
                    p1[row["query"]] = row["alt_count"]
        p2 = {}
        with open(input.p2_variants, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row["alt_count"]) > 4 and int(row["ref_count"])<4:
                    p2[row["query"]] = row["alt_count"]
        p3 = {}
        with open(input.p3_variants, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row["alt_count"]) > 8 and int(row["ref_count"])<4:
                    p3[row["query"]] = row["alt_count"]
        b12142 = {}
        with open(input.b12142_variants, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row["alt_count"]) > 1:
                    b12142[row["query"]] = row["alt_count"]

        with open(output.csv, "w") as fw:
            # "taxon,lineage,probability,pangoLEARN_version,status,note" 
            with open(input.csv, "r") as f:
                reader = csv.DictReader(f)
                header_names = reader.fieldnames
                writer = csv.DictWriter(fw, fieldnames=header_names,lineterminator='\n')
                writer.writeheader()

                for row in reader:
                    if row["lineage"] =="B.1.1.7" and row["taxon"] not in b117:
                        new_row = row
                        
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "B.1.1"

                        writer.writerow(new_row)

                    elif row["taxon"] in b117:
                        new_row = row
                        
                        snps = b117[row["taxon"]]
                        note = f"{snps}/17 B.1.1.7 SNPs"

                        new_row["note"] = note
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "B.1.1.7"

                        writer.writerow(new_row)
                    elif row["lineage"].startswith("B.1.351") and row["taxon"] not in b1351:
                        new_row = row
                        
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "B.1"

                        writer.writerow(new_row)
                        
                    elif row["taxon"] in b1351:
                        new_row = row
                        
                        snps = b1351[row["taxon"]]
                        note = f"{snps}/9 B.1.351 SNPs"

                        new_row["note"] = note
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "B.1.351"

                        writer.writerow(new_row)
                    elif row["taxon"] in p2:
                        new_row = row
                        
                        snps = p2[row["taxon"]]
                        note = f"{snps}/5 P.2 (B.1.1.28.2) SNPs"

                        new_row["note"] = note
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "P.2"

                        writer.writerow(new_row)
                    elif row["lineage"] =="P.2" and row["taxon"] not in p2:
                        new_row = row
                        
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "B.1.1.28"

                        writer.writerow(new_row)
                    elif row["taxon"] in p1:
                        new_row = row
                        
                        snps = p1[row["taxon"]]
                        note = f"{snps}/17 P.1 (B.1.1.28.1) SNPs"

                        new_row["note"] = note
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "P.1"

                        writer.writerow(new_row)
                    elif row["lineage"] =="P.1" and row["taxon"] not in p1:
                        new_row = row
                        
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "B.1.1.28"

                        writer.writerow(new_row)
                    elif row["taxon"] in p3:
                        new_row = row
                        snps = p3[row["taxon"]]
                        note = f"{snps}/12 P.3 (B.1.1.28.3) SNPs"

                        new_row["note"] = note
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "P.3"

                        writer.writerow(new_row)
                    elif row["lineage"] =="P.3" and row["taxon"] not in p3:
                        new_row = row
                        
                        new_row["probability"] = "1.0"
                        new_row["lineage"] = "B.1.1.28"

                        writer.writerow(new_row)
                    elif row["lineage"] == "B.1.214":
                        new_row = row
                        if row["taxon"] in b12142:
                            new_row["probability"] = "1.0"
                            new_row["lineage"] = "B.1.214.2"
                            snps = b12142[row["taxon"]]
                            note = f"{snps}/5 B.1.214.2 SNPs"
                            writer.writerow(new_row)
                        else:
                            writer.writerow(row)
                    else:
                        writer.writerow(row)
        print(pfunk.green(f"Output file written to: ") + f"{output.csv}")
        if config["alignment_out"]:
            print(pfunk.green(f"Output alignment written to: ") + config["outdir"] +"/sequences.aln.fasta")
rule report_results:
    input:
        csv = config["outfile"],
        lineages_csv = config["lineages_csv"]
    output:
        os.path.join(config["outdir"],"global_lineage_information.csv")
    shell:
        """
        report_results.py \
        -p {input.csv:q} \
        -b {input.lineages_csv:q} \
        -o {output:q} 
        """
