#!/bin/bash

oarsub -l '{mem>=150000}/nodes=1/core=4,walltime=1' --notify "mail:${EMAIL_ADDRESS}" -S './ecog.sh'
