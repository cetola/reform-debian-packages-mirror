#!/usr/bin/python3
import time, psutil, sys, getopt

def draw_bar(val, maxval):
	bars = ['▁','▁','▂','▂','▃','▄','▅','▆','▆','▇','█']
	val = max(0, min(val/maxval, 0.99))
	return bars[int(val*10)]

def draw_chart(lst, maxval):
	chart = ""
	l = len(lst)
	for x in range(l):
		chart += draw_bar(lst[l-x-1], maxval)
	return chart

def history_insert(lst, item, depth):
	lst.insert(0,item)
	if (len(lst) > depth): lst.pop()
	return lst

def main(argv):
	depth = 5
	interval = 0.3

	try:
		opts, args = getopt.getopt(argv,"hd:i:")
	except getopt.GetoptError:
		print ('compstat -d <number of bars> -i <interval in seconds, float>')
		sys.exit(2)
	for opt, arg in opts:
		if opt == '-d': depth = int(arg)
		elif opt == "-i": interval = float(arg)

	cpu_history = []
	read_history = []
	write_history = []
	ldisk_activity = psutil.disk_io_counters()

	while True:
		cpu_usage = psutil.cpu_percent()
		disk_activity = psutil.disk_io_counters()
		
		history_insert(cpu_history, cpu_usage, depth)	
		history_insert(read_history, disk_activity.read_bytes - ldisk_activity.read_bytes, depth)	
		history_insert(write_history, disk_activity.write_bytes - ldisk_activity.write_bytes, depth)
		
		print("CPU "+draw_chart(cpu_history, 100.0)+" R/W "+draw_chart(read_history, 1.0*1024*1024)+" "+draw_chart(write_history, 1.0*1024*1024), flush=True)
		
		ldisk_activity = disk_activity
		time.sleep(interval)

main(sys.argv[1:])


