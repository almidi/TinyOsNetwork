#include "SimpleRoutingTree.h"
#include <string.h>

module SRTreeC

#ifdef COLORS
	#define KNRM  "\x1B[0m"
	#define KRED  "\x1B[31m"
	#define KGRN  "\x1B[32m"
	#define KYEL  "\x1B[33m"
	#define KBLU  "\x1B[34m"
	#define KMAG  "\x1B[35m"
	#define KCYN  "\x1B[36m"
#endif
#ifndef COLORS
	#define KNRM  ""
	#define KRED  ""
	#define KGRN  ""
	#define KYEL  ""
	#define KBLU  ""
	#define KMAG  ""
	#define KCYN  ""
#endif

// Define Interfaces

{
	uses interface Boot;
	uses interface SplitControl as RadioControl;

	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	uses interface Packet as RoutingPacket;

	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;


	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as EpochTimer;
	uses interface Timer<TMilli> as SlotTimer;

	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;

	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;

	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;
	uses interface PacketQueue as DataQueue;

	uses interface Random as RandomGenerator;
	uses interface ParameterInit<uint16_t> as GeneratorSeed;
}

//Implement Network

implementation {
	// Epochs
	uint16_t  epochCounter;

	// Def Message Types
	// Messages for routing the network
	message_t radioRoutingSendPkt;
	// Messages towards parents
	message_t radioNotifySendPkt;

	bool RoutingSendBusy = FALSE;
	bool NotifySendBusy = FALSE;

	uint8_t curdepth;		//current depth
	uint8_t query1;			//Query 1
	uint8_t query2;			//Query 2
	uint8_t subquerys=0;	//Encoding of subquerys
	uint32_t subquery_b=0;	//Byte-Wise Encoding for Subquerys
	uint8_t numOfSubQ_b=0;	//Number of total bytes of subquerys
	uint8_t tct=0;			//Tina Threshlod
	uint16_t parentID;		//Parent Node ID
	uint32_t offset_milli;	//Timing for Slots

	bool TiNA; 

	//Query Encoding Matrix
	//Used to encode each query to 
	//5 fundemental subquerys
	uint8_t sqem[7]={0b00000,  //None
					 0b00001,  //Sum
					 0b00100,  //Count
					 0b01000,  //Max
					 0b10000,  //Min
					 0b00101,  //AVG
					 0b00111   //VAR
				};

	//subquery byte selection
	//                                                min--max--count--sqsum--sum
	uint32_t sqbem[5]={0b00000000000000000011, //Sum     -- 2bytes
					   0b00000000000001110000, //SumSq -- 3bytes
					   0b00000000000100000000, //Count  -- 1byte
					   0b00000001000000000000, //Max    -- 1byte
					   0b00010000000000000000  //Min     -- 1byte
				};
				
	//Calculated Data Matrix
	uint32_t cdm[5]={0, //Sum
					 0, //SqSum
					 0, //Count
					 0, //Max
					 0  //Min
				};
	//Calculated Data Matrix of last Epoch
	uint32_t tinacdm[5]={0, //Sum
				 		 0, //SqSum
				 		 0, //Count
				 		 0, //Max
				 		 0  //Min
				};

	//Root Data
	uint32_t qdm[6]={0, //Sum
					 0, //Count
					 0, //Max
					 0, //Min
					 0, //Avr
					 0  //Var
				};
	//Query Names
	char query_names[7][10] = {
                         "None ",
                         "SUM  ",
                         "COUNT",
                         "MAX  ",
                         "MIN  ",
                         "AVG  ",
                         "VAR  "
                     };
	

	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	task void startEpoch();
	task void enqueueData();
	task void calculateData();
	task void rootResults();
	task void measureData();

	// Set States
	void setRoutingSendBusy(bool state) {
		atomic {
			RoutingSendBusy = state;
		}
	}

	void setNotifySendBusy(bool state) {
		atomic {
			NotifySendBusy = state;
		}
		dbg("SRTreeC", "setNotifySendBusy(): NotifySendBusy = %s%s\n", (state == TRUE) ? "\x1B[31mTrue" : "\x1B[32mFalse",KNRM);
	}

	// Init cdm
	void initCdm(){
		cdm[0]= 0; //Sum
		cdm[1]=	0; //SqSum
		cdm[2]=	1; //Count
		cdm[3]=	0; //Max
		cdm[4]=	0; //Min
	}

	// Aggregate Data
	void aggregate(uint32_t* aggr, uint32_t* data){
		uint8_t i;

		// Sum
		aggr[0] += data[0];
		// SqSum
		aggr[1] += data[1];
		// Count
		aggr[2] += data[2];
		// Max
		aggr[3] = (aggr[3] > data[3]) ? aggr[3] : data[3];
		// Min
		aggr[4] = (aggr[4] < data[4]) ? aggr[4] : data[4];
	}

	// Pack Message Array
	void pack_bytes(nx_uint8_t* buffer,uint8_t* data){
		uint8_t i;
		uint8_t index=0;

		for(i=0;i<20;i++)
			if((subquery_b>>i)&1==1){
				buffer[index]=data[i];
		 		index++;
		}
	}

	// Unpack Message Array
	void unpack_bytes(nx_uint8_t* buffer,uint8_t* data){
		uint8_t i;
		uint8_t index=0;

		for(i=0;i<20;i++)
			if((subquery_b>>i)&1==1){
				data[i]=buffer[index];
		 		index++;
			}
			else{
				data[i]=0;
			}
	}

	// Calculate Root Querys
	void calculateQ(){
		qdm[0] = cdm[0]; 									//Sum
		qdm[1] = cdm[2]; 									//Count
		qdm[2] = cdm[3]; 									//Max
		qdm[3] = cdm[4]; 									//Min
		qdm[4] = cdm[0]/cdm[2];								//AVG
		qdm[5] = (cdm[1]/cdm[2]) - pow((cdm[0]/cdm[2]),2); 	//VAR
	}

	// Calculates SubQuerys number from query1 and query2
	void calculateSubQ(){
		uint8_t i;

		// calculate subquerys
		if (query1 > 6 || query2 > 6){
			dbg("Query", "calculateSubQ(): %sUnknown Query %s\n",KRED,KNRM);
			return;
		}

		subquerys = 0;
		subquerys = subquerys | sqem[query1];
		subquerys = subquerys | sqem[query2];


		//calculate subquerys byte encoding
		for(i=0;i<5;i++){
			if(((subquerys >> i)&1) == 1){
				subquery_b = subquery_b | sqbem[i];
			}
		}

		// calculate number of subquery bytes
		numOfSubQ_b = 0;
		for(i=0;i<20;i++){
			if(((subquery_b >> i)&1) == 1){numOfSubQ_b++;}
		}

		dbg("Query", "calculateSubQ(): Calculcated subquerys=%s %d%s,  subquery_b=%s %d%s, numOfSubQ_b=%s %d%s\n",KYEL,subquerys,KNRM,KYEL, subquery_b,KNRM,KYEL, numOfSubQ_b,KNRM);
	}

	// Checks if Delta of subquery is big enough to be sent. (there MUST be only ONE subquery)
	bool checkTiNA(){
		uint8_t i;
		uint8_t subq=0;
		// find used subquery
		for(i=0;i<5;i++){
			if((subquerys>>i)&1==1){
				subq=i;
		 		break;
			}
		}
		if(tinacdm[i]==0 && cdm[i]>0)
			return 1;

		if(tinacdm[i]==0)
			return 0;

		if((abs((cdm[i]-tinacdm[i])/(tinacdm[i]))*100)>tct)
			return 1;

		return 0;
	}

	// Boot of device
	event void Boot.booted() {
		uint8_t i ;
		
		// Start Radio
		call RadioControl.start();

		//epoch counter
		epochCounter = 0;

		//Initialize data
		initCdm();

		//Init RandomGenerator, Use Time for seed
		call GeneratorSeed.init(time(NULL)+TOS_NODE_ID);

		// If Root Node
		if (TOS_NODE_ID == 0) {
			// Root Node = 0 Depth
			curdepth = 0;
			parentID = 0;
			//calculate tct
			tct = (call RandomGenerator.rand32() % (TCT_UPPER_BOUND-TCT_LOWER_BOUND))+TCT_LOWER_BOUND;
			//decide randomly if TiNA
			TiNA = (call RandomGenerator.rand32()%2);
			// TiNA = 0; //for debug purposes
			//calculate random querys
			query1 = (call RandomGenerator.rand32() % (6-(2*TiNA)))+1;
			query2 = (call RandomGenerator.rand32() % 6)+1;
			//delete query2 randomly or if query2 == query1 or if TiNA algorithm is enabled
			if((call RandomGenerator.rand32()%2) || (query1 == query2 || TiNA)){query2 = 0;}
			dbg("Boot", "%sROOT Node Booted:%s curdepth = %s%03d%s  , parentID = %s%d%s\n",KYEL, KNRM, KYEL,curdepth, KNRM,KYEL,parentID, KNRM);
			dbg("Boot", "%s                :%s Query1   = %s%s%s, Query2   = %s%s%s\n",KYEL, KNRM, KYEL, query_names[query1], KNRM, KYEL,query_names[query2], KNRM);
			if(TiNA){
				dbg("Boot", "                %s:%s TiNA Mode %sEnabled%s, tct = %s%d%%%s\n",KYEL,KNRM,KGRN,KNRM,KYEL,tct,KNRM);
			}
		

		} else {
			//-1 = Undefined Depth (will be calculated later)
			curdepth = -1;
			parentID = -1;
			query1 = 0;	
			query2 = 0;
			dbg("Boot", "%s     Node Booted:%s curdepth = %03d  ,  parentID= %d\n",KYEL, KNRM, curdepth , parentID);	
		}		
	}

	// Radio Started
	event void RadioControl.startDone(error_t err) {
		if (err == SUCCESS) {
			dbg("Radio" , "RadioControl.StartDone():%s Radio initialized successfully!!!%s\n",KYEL,KNRM);
			// Start Routing (on first epoch only)
			if (TOS_NODE_ID == 0) {
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		} else {
			dbg("Radio" , "RadioControl.StartDone():%s Radio initialization failed! Retrying...%s\n",KRED,KNRM);
			call RadioControl.start();
		}
	}

	// Radio Stopped
	event void RadioControl.stopDone(error_t err) {
		dbg("Radio", "RadioControl.stopDone():%s Radio stopped!%s\n",KYEL,KNRM);	
	}

	// Timer for Routing
	event void RoutingMsgTimer.fired() {
		// temp message
		message_t tmp;
		error_t enqueueDone;
		uint8_t query;
		uint32_t len;

		RoutingMsg* mrpkt;
		RoutingMsgTiNA* mrpktt;

		dbg("Routing", "RoutingMsgTimer fired! -----------------------------------------------------------------\n");
		dbg("Routing", "RoutingMsgTimer.fired(): radioBusy = %s %s\n", (RoutingSendBusy) ? "\x1B[31mTrue" : "\x1B[32mFalse",KNRM);
		
		if (TOS_NODE_ID == 0) {

			// add some color to your life
			dbg("Routing","%s\n",KCYN);
			dbg("Routing", "######################################################################################## \n");
			dbg("Routing", "################################   Initialized Routing   ############################### \n");
			dbg("Routing", "########################################################################################%s\n",KNRM);
			dbg("Routing","\n");
		}


		if (call RoutingSendQueue.full()) {
			dbg("Routing", "RoutingMsgTimer.fired(): %sRouting Send Q Full... %s\n",KRED,KNRM);
			return;
		}

		// Encode Query
		query = query2 << 3;
		query = query | query1;

		// Make a routing package 
		if(TiNA){
			mrpktt = (RoutingMsgTiNA*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsgTiNA)));
		}
		else{
			mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		}

		// mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if (mrpkt == NULL) {
			dbg("Routing", "RoutingMsgTimer.fired(): %sNo valid payload... %s\n",KRED,KNRM);
			return;
		}

		if(TiNA){
			mrpktt = (RoutingMsgTiNA*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsgTiNA)));
			len = sizeof(RoutingMsgTiNA);
			// Fill package
			atomic {
				mrpktt->depth = curdepth;
				mrpktt->query = query;
				mrpktt->tct=tct;
			}
		}
		else{
			mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
			len = sizeof(RoutingMsg);
			// Fill package
			atomic {
				mrpkt->depth = curdepth;
				mrpkt->query = query;
			}
		}

		


		// Send Routing Package
		dbg("Routing" , "RoutingMsgTimer.fired(): Sending RoutingMsg... \n");

		//Set Destination Addr
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		//Set Payload length
		call RoutingPacket.setPayloadLength(&tmp, len);
		//Add msg to RoutingMSG Queue
		enqueueDone = call RoutingSendQueue.enqueue(tmp);
		//Check if packet enqueued successfully 
		if (enqueueDone == SUCCESS) {
			dbg("Routing", "RoutingMsgTimer.fired(): %sRoutingMsg enqueued successfully in SendingQueue!!!%s\n",KGRN,KNRM);
			if (call RoutingSendQueue.size() == 1) {
				dbg("Routing", "RoutingMsgTimer.fired(): %sSendTask() posted!!%s\n",KGRN,KNRM);
				post sendRoutingTask();
			}
			else{
				dbg("Routing", "RoutingMsgTimer.fired(): %sRouting Msg Queued Unsuccesfully %s\n",KRED,KNRM);
			}
		} else {
			dbg("Routing", "RoutingMsgTimer.fired(): %sRoutingMsg failed to be enqueued in SendingQueue!!!%s\n",KRED,KNRM);
		}

		//calculate subquerys(for self)
		calculateSubQ();

		//Start your epoch
		post startEpoch();
	}

	// Timer for epoch periods
	event void EpochTimer.fired() {
		uint32_t rand_off;
		epochCounter++ ;
		dbg("Timing", "EpochTimer.fired(): %s######################################################## EPOCH %d %s\n",KCYN,epochCounter,KNRM);

		//random offset granularity (how many possible sub-slots)
		#define granularity 50

		// Calculate a small random offset 
		rand_off = (call RandomGenerator.rand32() % granularity)*((EPOCH_PERIOD_MILLI/MAX_DEPTH)/granularity);

		//Restart Timer
		call EpochTimer.startOneShot(EPOCH_PERIOD_MILLI);
		//(Re)start Slot Timer
		call SlotTimer.startOneShot(offset_milli-rand_off);
		
		post measureData();
	}

	// Timer to send data
	event void SlotTimer.fired() {
		dbg("Timing", "SlotTimer.fired(): %sTime to Send Data %s\n",KYEL,KNRM);
		//calculateData
		post calculateData();
	}

	// Routing Message Sent
	event void RoutingAMSend.sendDone(message_t * msg , error_t err) {
		dbg("Routing", "RoutingAMSend.sendDone(): A Routing package sent... %s %s\n", (err == SUCCESS) ? "\x1B[32mTrue" : "\x1B[31mFalse",KNRM);
		setRoutingSendBusy(FALSE);

		if (!(call RoutingSendQueue.empty())) {
			post sendRoutingTask();
		}
	}

	// Notify Message Sent
	event void NotifyAMSend.sendDone(message_t *msg , error_t err) {
		dbg("SRTreeC", "NotifyAMSend.sendDone(): A Notify package sent... %s %s\n", (err == SUCCESS) ? "\x1B[32mTrue" : "\x1B[31mFalse",KNRM);
		setNotifySendBusy(FALSE);

		if (!(call NotifySendQueue.empty())) {
			post sendNotifyTask();
		}
	}

	// Notification Message Received
	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len) {
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		//return the source address of the packet
		msource = call NotifyAMPacket.source(msg);

		dbg("NotifyParentMsg", "NotifyReceive.receive(): Something received!!! from %u\n", msource);

		atomic {
			memcpy(&tmp, msg, sizeof(message_t));
		}
		enqueueDone = call NotifyReceiveQueue.enqueue(tmp);

		if ( enqueueDone == SUCCESS) {
			post receiveNotifyTask();
		}

		dbg("NotifyParentMsg", "NotifyReceive.receive(): NotifyMsg enqueue %s!!! %s\n",(enqueueDone == SUCCESS) ? "\x1B[32mSuccessful" : "\x1B[31mFailed",KNRM);

		return msg;
	}

	// Routing Message Received
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len) {
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;

		msource = call RoutingAMPacket.source(msg);

		dbg("Routing", "RoutingReceive.receive(): Something received!!!  from %u \n", msource);

		if(len!=sizeof(RoutingMsg)&&len!=sizeof(RoutingMsgTiNA))
		{
		dbg("SRTreeC","RoutingReceive.receive() %sUnknown message received!!!%s\n",KRED,KNRM);
		return msg;
		}

		atomic {
			memcpy(&tmp, msg, sizeof(message_t));
			//tmp=*(message_t*)msg;
		}
		enqueueDone = call RoutingReceiveQueue.enqueue(tmp);


		if ( enqueueDone == SUCCESS) {
			post receiveRoutingTask();
		}

		dbg("Routing", "RoutingReceive.receive(): RoutingMsg enqueue %s %s\n",(enqueueDone == SUCCESS) ? "\x1B[32mSuccessful" : "\x1B[31mFailed",KNRM);


		return msg;
	}

	//////////////////////////////////// Tasks implementations ////////////////////////////////////

	// Dequeues a routing message and sends it
	task void sendRoutingTask() {
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;

		if (call RoutingSendQueue.empty()) {
			dbg("Routing", "sendRoutingTask(): %sQ is empty%s\n",KRED,KNRM);
			return;
		}

		//Check Mutex
		if (RoutingSendBusy) {
			dbg("Routing", "sendRoutingTask(): %sRoutingSendBusy= TRUE%s\n",KRED,KNRM);
			return;
		}

		radioRoutingSendPkt = call RoutingSendQueue.dequeue();

		mlen = call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest = call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if (mlen != sizeof(RoutingMsg) && mlen != sizeof(RoutingMsgTiNA)) {
			dbg("Routing", "sendRoutingTask(): %sUnknown message%s\n",KRED,KNRM);
			return;
		}

		//Mutex
		setRoutingSendBusy(TRUE);
		sendDone = call RoutingAMSend.send(mdest, &radioRoutingSendPkt, mlen);

		if ( sendDone != SUCCESS) {
			call RoutingSendQueue.enqueue(radioRoutingSendPkt);
		}
		setRoutingSendBusy(FALSE);

		dbg("Routing", "sendRoutingTask(): Send %s %s\n",(sendDone == SUCCESS) ? "\x1B[32mSuccessful" : "\x1B[31mFailed",KNRM);
	}

	// Dequeues a notification message and sends it
	task void sendNotifyTask() {
		uint8_t mlen;
		error_t sendDone;
		uint16_t mdest;
		void* mpayload;

		if (call NotifySendQueue.empty()) {
			dbg("SRTreeC", "sendNotifyTask(): Q is empty!\n");
			return;
		}

		if (NotifySendBusy == TRUE) {
			dbg("SRTreeC", "sendNotifyTask(): NotifySendBusy= TRUE!!!\n");
			return;
		}

		//dequeue packet
		radioNotifySendPkt = call NotifySendQueue.dequeue();

		//get payload length
		mlen = call NotifyPacket.payloadLength(&radioNotifySendPkt);

		//get payload
		mpayload = call NotifyPacket.getPayload(&radioNotifySendPkt, mlen);

		// check if message is known
		if (mlen != numOfSubQ_b) {
			dbg("SRTreeC", "\t\t sendNotifyTask(): Unknown message!!\n");
			return;
		}

		dbg("SRTreeC" , "sendNotifyTask(): mlen = %u  senderID= %u \n", mlen, call NotifyAMPacket.source(&radioNotifySendPkt));
		mdest = call NotifyAMPacket.destination(&radioNotifySendPkt);

		//send notification packet
		sendDone = call NotifyAMSend.send(mdest, &radioNotifySendPkt, mlen);

		if ( sendDone == SUCCESS) {
			dbg("SRTreeC", "sendNotifyTask(): %sSend Success!!!%s\n",KGRN,KNRM);
		} else {
			dbg("SRTreeC", "sendNotifyTask(): %sSend Failed!!!%s\n",KRED,KNRM);
			setNotifySendBusy(FALSE);
		}
	}

	// Dequeues a routing message and processes it
	task void receiveRoutingTask() {
		message_t tmp;
		error_t enqueueDone;
		uint8_t len;
		uint16_t oldparentID;
		message_t radioRoutingRecPkt;
		uint8_t query;

		RoutingMsg * mpkt;
		RoutingMsgTiNA * mpktt;

		// Dequeues the message
		radioRoutingRecPkt = call RoutingReceiveQueue.dequeue();
		// Length of message 
		len = call RoutingPacket.payloadLength(&radioRoutingRecPkt);

		dbg("Routing", "ReceiveRoutingTask(): Function called with packet length =%u \n", len);
		
		// Check if NODE is orphan
		if ( (parentID >= 0) && (parentID < 65535))
			return;

		
		// Processing Radio Packet
		if (len == sizeof(RoutingMsg)) {	
			mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt, len));
			dbg("Routing" , "receiveRoutingTask(): Routing Message Packet -> senderID= %d , senderDepth= %d , size= %d \n",call RoutingAMPacket.source(&radioRoutingRecPkt) , mpkt->depth,sizeof(mpkt));	
			// Sender is the parent
			parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
			// Calculate current depth
			curdepth = mpkt->depth + 1;
			//Take encoded query
			query = mpkt->query;
			//Disable TiNA
			TiNA = 0; 
		}else if (len == sizeof(RoutingMsgTiNA)){
			mpktt = (RoutingMsgTiNA*) (call RoutingPacket.getPayload(&radioRoutingRecPkt, len));
			dbg("Routing" , "receiveRoutingTask(): Routing Message Packet -> senderID= %d , senderDepth= %d , size= %d \n",call RoutingAMPacket.source(&radioRoutingRecPkt) , mpktt->depth,sizeof(mpktt));	
			// Sender is the parent
			parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
			// Calculate current depth
			curdepth = mpktt->depth + 1;
			//Take encoded query
			query = mpktt->query;
			//Enable TiNA
			TiNA =1; 
			//Get tct
			tct = mpktt->tct;
		}
		else {
			dbg("Routing", "receiveRoutingTask(): %sWrong message%s\n",KRED,KNRM);
			return;
		}

		//Decode remaining query
		query1= query & 7;
		query2= query >> 3;
		// Calculate SubQuerys
		calculateSubQ();
		dbg("Routing" , "receiveRoutingTask(): %sNode routed -> Parent = %s%d%s, Depth = %s%d%s\n",KBLU, KYEL, parentID, KBLU, KYEL, curdepth, KNRM);
		dbg("Query" , "receiveRoutingTask(): %sQuery Requests Received: Query1 = %s%s%s, Query2 = %s%s%s,TiNA = %s%s%s\n",KBLU, KYEL,query_names[query1],KBLU,KYEL, query_names[query2],KBLU,KYEL, (TiNA == TRUE) ? "True" : "False", KNRM);
		// Route your children
		dbg("Routing", "receiveRoutingTask(): Call RoutingMsgTimer to route children%s\n",KNRM);
		if (TOS_NODE_ID != 0) {
			call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
		}
	}

	// dequeues a notification message and processes it
	task void receiveNotifyTask() {
		uint8_t len;
		uint8_t i;
		message_t radioNotifyRecPkt;
		message_t tmp;
		bool found = 0;
		nx_uint16_t SID;
		uint32_t hd;

		//dequeue message
		radioNotifyRecPkt = call NotifyReceiveQueue.dequeue();

		len = call NotifyPacket.payloadLength(&radioNotifyRecPkt);

		dbg("NotifyParentMsg", "ReceiveNotifyTask(): len=%u \n", len);
		// check if packet is correct
		if (len == numOfSubQ_b) {
			dbg("NotifyParentMsg" , "NotifyParentMsg received from %d !!! \n", call NotifyAMPacket.source(&radioNotifyRecPkt));
			// If packet is for me
			if ( call NotifyAMPacket.destination(&radioNotifyRecPkt) == TOS_NODE_ID) {

				//UPDATE DataQueue -------------------------------------------------------------------------------------
				//Get Message Sender ID
				SID = call NotifyAMPacket.source(&radioNotifyRecPkt);

				// Search for that sender in DataQueue
				for(i=0;i< call DataQueue.size();i++){
					tmp = call DataQueue.dequeue();
					len = call NotifyPacket.payloadLength(&tmp);

					//If message isnt from the same sender
					if(call NotifyAMPacket.source(&tmp) != SID){
						//Enqueue old message
						call DataQueue.enqueue(tmp);
					}
					else{
						//Enqueue new message
						dbg("NotifyParentMsg", "receiveNotifyTask():Enqueued updated message in DataQueue \n");
						call DataQueue.enqueue(radioNotifyRecPkt);
						found = 1;
						break;
					}
				}

				//If there wasnt any message in DataQueue from the same sender, enqueue new message
				if(!found){
					call DataQueue.enqueue(radioNotifyRecPkt);
					dbg("NotifyParentMsg", "receiveNotifyTask():Enqueued new message in DataQueue \n");
				}
				//------------------------------------------------------------------------------------------------------		
			}
		// packet is not correct
		} else {
			dbg("NotifyParentMsg", "receiveNotifyTask():%sWrong message!!!%s \n",KRED,KNRM);
			return;
		}
	}

    // Start The Epoch
	task void startEpoch(){
		//Start Epoch Timer
		call EpochTimer.startOneShot(TIMER_FAST_PERIOD);
		//Calculate offset milli (for sending measurements)
		offset_milli = EPOCH_PERIOD_MILLI / MAX_DEPTH;
		offset_milli = offset_milli*(MAX_DEPTH - curdepth);

		dbg("Timing", "startEpoch(): %sStarted Epoch Timer. Offset Milli = %d%s\n",KCYN,offset_milli, KNRM);
	}

	//Measure Data
	task void measureData(){
		uint32_t measurement;
		//Produce new Measurement
		measurement = call RandomGenerator.rand16() % 51; // range [0,50]
		dbg("Measure", "EpochTimer.fired(): %sEpoch: %s%d %sMeasured: %s%d%s\n",KMAG,KYEL, epochCounter,KMAG,KYEL,measurement, KNRM);


		//Initialize cdm with Measurements
		cdm[0] = measurement; 			//Sum
		cdm[1] = pow(measurement,2); 	//SqSum
		cdm[2] = 1; 					//Count
		cdm[3] = measurement; 			//Max
		cdm[4] = measurement; 			//Min
	}

	// Aggregates data from DataQueue
	task void calculateData(){
		uint8_t len;
		uint8_t i;
		message_t tmp;
		void* mr;
		nx_uint32_t packet_data[4];
		nx_uint32_t unpacked[5];

		// Iterate Data Queue
		for(i=0;i< call DataQueue.size();i++){
			//dequeue
			tmp = call DataQueue.dequeue();

			//get payload
			len = call NotifyPacket.payloadLength(&tmp);
			mr = call NotifyPacket.getPayload(&tmp, len);

			//get data
			memcpy(packet_data,mr,len*sizeof(nx_uint8_t));

			//unpack data
			unpack_bytes((uint8_t*) packet_data,(uint8_t*) unpacked);

			//aggregate data
			aggregate(cdm, unpacked);

			//enqueue back to DataQueue
			call DataQueue.enqueue(tmp);
		}

		//Enqueue calculate data to be sended or just print them (if ROOT node)
		if (TOS_NODE_ID == 0){
			post rootResults();
		} else{
			post enqueueData();
		}
	}

	// Enqueues data on a notification message Q and calls sendNotifyTask()
	task void enqueueData(){
		message_t tmp;
		nx_uint8_t  byte_buffer[20];
		void* m;
		int len;

		//If TiNA protocol is enabled, and this is not the first epoch, check to see if data is worth sending
		if(TiNA && !checkTiNA()&& (epochCounter>0)){
			dbg("NotifyParentMsg", "enqueueData():%s TiNA - Not Sending Message\n%s",KRED,KNRM);
			return;
		}

		//If TiNA is enabled and data are worh sending, save data for next epoch checking
		if(TiNA){memcpy(tinacdm,cdm,sizeof(tinacdm));}

		m = call NotifyPacket.getPayload(&tmp,numOfSubQ_b*sizeof(nx_uint8_t)); 
		
		// Pack Calculated Data
		pack_bytes(byte_buffer,(uint8_t*) cdm);
		// Copy packed data to packet
		memcpy(m,byte_buffer,numOfSubQ_b*sizeof(nx_uint8_t));

		call NotifyAMPacket.setDestination(&tmp, parentID);
		call NotifyAMPacket.setType(&tmp,AM_NOTIFYPARENTMSG);
		call NotifyPacket.setPayloadLength(&tmp, numOfSubQ_b);



		// Enqueue packet to be sent
		if (call NotifySendQueue.enqueue(tmp) == SUCCESS) {
			dbg("NotifyParentMsg", "enqueueData(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
			if (call NotifySendQueue.size() == 1) {
				// send the packet
				post sendNotifyTask();
			}
		}
	}

	// Makes final calculations and presents root data
	task void rootResults(){
		//calculate final querys
		calculateQ();

		dbg("Root", "rootResults(): %s##################################### ROOT RESULTS FOR EPOCH %d ####%s\n",KBLU,epochCounter,KNRM);
		dbg("Root", "rootResults(): %s## Query 1: %s%s%s -- Result: %s%d%s\n",KBLU,KGRN, query_names[query1],KBLU ,KGRN, qdm[query1-1],KNRM);
		if(query2>0){dbg("Root", "rootResults(): %s## Query 2: %s%s%s -- Result: %s%d%s\n",KBLU,KGRN, query_names[query2],KBLU ,KGRN, qdm[query2-1],KNRM);}
		dbg("Root", "\n");
		
		
	}

}
