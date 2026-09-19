# S7.9 Vision Feasibility Spike

## Overview
This spike tests the feasibility of using the macOS `Vision` framework (`VNClassifyImageRequest`) for identifying specific home items. Since downloading from traditional image APIs was network blocked, we generated 1 highly realistic photo per category and processed them locally with `VNClassifyImageRequest`. 

## Results

| Class | Image Name | Top 5 Labels (Confidence) | Usable Mapping? |
|-------|------------|----------------------------|-----------------|
| Space Heater | space_heater_1_1789085878776.jpg | structure (96.01%), wood_processed (91.11%), art (82.60%), decoration (82.57%), frame (82.57%) | NO |
| Water Heater | water_heater_1_1789085888993.jpg | structure (92.78%), conveyance (92.78%), portal (92.77%), window (92.77%), material (35.56%) | NO |
| Bookcase | bookcase_1_1789085922042.jpg | structure (98.38%), conveyance (89.57%), portal (89.57%), window (89.55%), art (85.29%) | NO |
| Wall-mounted TV | wall_mounted_tv_1_1789085930002.jpg | consumer_electronics (76.71%), machine (76.71%), television (76.71%), structure (75.75%), wood_processed (64.40%) | YES |
| Wall Mirror | wall_mirror_1_1789085938607.jpg | structure (72.14%), furniture (64.63%), art (63.28%), decoration (63.28%), frame (63.28%) | NO |
| Radiator | radiator_1_1789085948483.jpg | structure (93.68%), wood_processed (87.94%), art (85.66%), decoration (85.64%), frame (85.64%) | NO |
| Box Fan | box_fan_1_1789085957475.jpg | structure (92.17%), machine (88.72%), appliance (88.72%), electric_fan (88.72%), wood_processed (80.71%) | YES |
| Dresser | dresser_1_1789085968790.jpg | structure (98.79%), furniture (92.96%), cabinet (91.50%), conveyance (87.24%), portal (87.24%) | YES |
| Plain Window | plain_window_1_1789085990625.jpg | structure (91.07%), conveyance (91.07%), portal (91.07%), window (91.06%), plant (33.69%) | YES |

## GATE
The target classes are: Space Heater, Water Heater, Bookcase, Wall-mounted TV, Wall Mirror.
Number of target classes with a usable mapping: 1 (Television).

Because fewer than two target classes were recognized correctly (1 < 2), the verdict is **NO-GO**.
