# axi-util
AXI &amp; other utilities

* axiPipeRW - Allows streaming data from/to HPS (hard processor system). Uses one AXI-mm slave for configuration (buffer addresses) and one AXI-mm master for reading/writing data to main memory.
* axiBlockProcessorAdapter2 - Adapts a block processor (e.g. FFT) to AXI streams. Handles flushing of the block processor pipeline and priming prior to each frame.
* dcfifo - Dual clock AXI stream FIFO
* dcfifo2 - Dual clock AXI stream FIFO, supports different input/output data widths
* dcfifo2_wrapper - Allows using dcfifo2 in Vivado block designs
