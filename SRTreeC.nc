#include "SimpleRoutingTree.h"

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
	uses interface Timer<TMilli> as LostTaskTimer;
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
	bool lostRoutingSendTask = FALSE;
	bool lostNotifySendTask = FALSE;
	bool lostRoutingRecTask = FALSE;
	bool lostNotifyRecTask = FALSE;

	uint8_t curdepth;
	uint8_t query1;
	uint8_t query2;
	uint8_t subquerys=0;
	uint8_t numOfSubQ=0;
	uint16_t parentID;
	uint32_t offset_milli;

	//Pack/Unpack Buffer
	uint32_t buffer[5];

	// Aggregated Data
	uint32_t SUM;
	uint32_t COUNT;
	uint32_t MAX;

	//Query Encoding Matrix
	//Used to encode each query to 
	//5 fundemental subquerys
	uint8_t qem[6]={0b00001,  //Sum
					0b00100,  //Count
					0b01000,  //Max
					0b10000,  //Min
					0b00101,  //AVG
					0b00110   //VAR
				};

	//Calculated Data Matrix
	uint32_t cdm[5]={0, //Sum
					0, //SqSum
					0, //Count
					0, //Max
					0  //Min
				};
	
	//Message sizes
	uint8_t ms[4]={sizeof(NotifyParentMsgSingle),
				   sizeof(NotifyParentMsgDouble),
				   sizeof(NotifyParentMsgTriple),
				   sizeof(NotifyParentMsgQuad)
				};

	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	task void startEpoch();
	task void enqueueData();
	task void calculateData();
	task void rootResults();
	task void calculateSubQ();


	// Set States
	void setLostRoutingSendTask(bool state) {
		atomic {
			lostRoutingSendTask = state;
		}
		if (state == TRUE) {
		} else {
		}
	}

	void setLostNotifySendTask(bool state) {
		atomic {
			lostNotifySendTask = state;
		}

		if (state == TRUE) {
		} else {
		}
	}

	void setLostNotifyRecTask(bool state) {
		atomic {
			lostNotifyRecTask = state;
		}
	}

	void setLostRoutingRecTask(bool state) {
		atomic {
			lostRoutingRecTask = state;
		}
	}

	void setRoutingSendBusy(bool state) {
		atomic {
			RoutingSendBusy = state;
		}
		if (state == TRUE) {
		} else {
		}
	}

	void setNotifySendBusy(bool state) {
		atomic {
			NotifySendBusy = state;
		}
		dbg("SRTreeC", "setNotifySendBusy(): NotifySendBusy = %s%s\n", (state == TRUE) ? "\x1B[31mTrue" : "\x1B[32mFalse",KNRM);

		if (state == TRUE) {
		} else {
		}
	}
	//Message Data Seters
	void setSenderID(void* m,nx_uint16_t SID){
		switch (numOfSubQ){
			case 1:
				((NotifyParentMsgSingle*) m)->senderID = SID;
				break;
			case 2:
				((NotifyParentMsgDouble*) m)->senderID = SID;
				break;
			case 3:
				((NotifyParentMsgTriple*) m)->senderID = SID;
				break;
			case 4:
				((NotifyParentMsgQuad*) m)->senderID = SID;
				break;
		}
	}

	void setParentID(void* m,nx_uint16_t PID){
		switch (numOfSubQ){
			case 1:
				((NotifyParentMsgSingle*) m)->parentID = PID;
				break;
			case 2:
				((NotifyParentMsgDouble*) m)->parentID = PID;
				break;
			case 3:
				((NotifyParentMsgTriple*) m)->parentID = PID;
				break;
			case 4:
				((NotifyParentMsgQuad*) m)->parentID = PID;
				break;
		}
	}

	void setDepth(void* m,nx_uint8_t dep){
		switch (numOfSubQ){
			case 1:
				((NotifyParentMsgSingle*) m)->depth = dep;
				break;
			case 2:
				((NotifyParentMsgDouble*) m)->depth = dep;
				break;
			case 3:
				((NotifyParentMsgTriple*) m)->depth = dep;
				break;
			case 4:
				((NotifyParentMsgQuad*) m)->depth = dep;
				break;
		}
	}

	//Message Data Geters

	nx_uint16_t getSenderID(void* m){
		switch (numOfSubQ){
			case 1:
				return(((NotifyParentMsgSingle*) m)->senderID);
			case 2:
				return(((NotifyParentMsgDouble*) m)->senderID);
			case 3:
				return(((NotifyParentMsgTriple*) m)->senderID);
			case 4:
				return(((NotifyParentMsgQuad*) m)->senderID);	
		}
	}

	nx_uint16_t getParentID(void* m){
		switch (numOfSubQ){
			case 1:
				return(((NotifyParentMsgSingle*) m)->parentID);
			case 2:
				return(((NotifyParentMsgDouble*) m)->parentID);
			case 3:
				return(((NotifyParentMsgTriple*) m)->parentID);
			case 4:
				return(((NotifyParentMsgQuad*) m)->parentID);
		}
	}

	nx_uint8_t getDepth(void* m){
		switch (numOfSubQ){
			case 1:
				return(((NotifyParentMsgSingle*) m)->depth);
			case 2:
				return(((NotifyParentMsgDouble*) m)->depth);
			case 3:
				return(((NotifyParentMsgTriple*) m)->depth);
			case 4:
				return(((NotifyParentMsgQuad*) m)->depth);
		}
	}

	nx_uint32_t* getNumPtr(void* m){
		switch (numOfSubQ){
			case 1:
				return (((NotifyParentMsgSingle*) m)->Num);
			case 2:
				return (((NotifyParentMsgDouble*) m)->Num);
			case 3:
				return (((NotifyParentMsgTriple*) m)->Num);
			case 4:
				return (((NotifyParentMsgQuad*) m)->Num);
		}
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
	void aggregate(uint8_t calc, uint32_t value){
		switch(calc){
			// SUM
			case 0:
				cdm[calc] += value;
				break;
			// SqSUM
			case 1:
				cdm[calc] += (value^2);
				break;
			// Count
			case 2:
				cdm[calc] += value;
				break;
			// MAX
			case 3:
				cdm[calc] = (cdm[calc] > value) ? cdm[calc] : value;
				break;
			// MIN
			case 4:
				cdm[calc] = (cdm[calc] < value) ? cdm[calc] : value;
				break;
			// Other
			default:
				break;
		}
		return;
	}

	// Pack Message Array
	void pack(nx_uint32_t* m_array,uint32_t* d_array){
		uint8_t i;
		uint8_t index=0;
		uint8_t TempNumOfSubQ=numOfSubQ;

		m_array[0]=1;

		//  for(i=0;i<5;i++)
		//  	if((TempNumOfSubQ>>i)&1==1){
		//  		m_array[index]=d_array[i];
		//  		index++;
		//  	}
	}

	// Boot of device
	event void Boot.booted() {
		// Start Radio
		call RadioControl.start();

		//epoch counter
		epochCounter = 0;

		//init values
		SUM = 0;
		COUNT = 1;
		MAX = 0;

		//2.0
		cdm[0]=0;
		cdm[1]=0;
		cdm[2]=0;
		cdm[3]=0;
		cdm[4]=0;


		//Init RandomGenerator
		call GeneratorSeed.init(TOS_NODE_ID);

		// If Root Node
		if (TOS_NODE_ID == 0) {
			// Root Node = 0 Depth
			curdepth = 0;
			parentID = 0;
			//calculate random querys
			query1 = (call RandomGenerator.rand16() % 5)+1;
			query2 = (call RandomGenerator.rand16() % 5)+1;
			//delete query2 randomly or if query2 == query1
			if(call RandomGenerator.rand16()%1 || query1 == query2){query2 = 0;}
			dbg("Boot", "%sROOT Node Booted:%s curdepth = %03d  ,  parentID= %d, Query1 = %d, Query2 = %d\n",KYEL, KNRM, curdepth, parentID, query1, query2);

		} else {
			//-1 = Undefined Depth (will be calculated later)
			curdepth = -1;
			parentID = -1;
			query1 = 0;	
			query2 = 0;
			dbg("Boot", "%sNode Booted:%s curdepth = %03d  ,  parentID= %d\n",KYEL, KNRM, curdepth , parentID);	
		}		
	}

	// Radio Started
	event void RadioControl.startDone(error_t err) {
		if (err == SUCCESS) {
			dbg("Radio" , "RadioControl.StartDone():%s Radio initialized successfully!!!%s\n",KYEL,KNRM);

			//call RoutingMsgTimer.startOneShot(MAX_DEPTH);
			//call RoutingMsgTimer.startPeriodic(MAX_DEPTH);
			//call LostTaskTimer.startPeriodic(SEND_CHECK_MILLIS);

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

	// Timer for lost tasks TODO: Unused
	event void LostTaskTimer.fired() {
		if (lostRoutingSendTask) {
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}

		if (lostNotifySendTask) {
			post sendNotifyTask();
			setLostNotifySendTask(FALSE);
		}

		if (lostRoutingRecTask) {
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}

		if (lostNotifyRecTask) {
			post receiveNotifyTask();
			setLostNotifyRecTask(FALSE);
		}
	}

	// Timer for Routing
	event void RoutingMsgTimer.fired() {
		// temp message
		message_t tmp;
		error_t enqueueDone;
		uint8_t query;

		RoutingMsg* mrpkt;
		dbg("Routing", "RoutingMsgTimer fired! -----------------------------------------------------------------\n");
		dbg("Routing", "RoutingMsgTimer.fired(): radioBusy = %s %s\n", (RoutingSendBusy) ? "\x1B[31mTrue" : "\x1B[32mFalse",KNRM);
		
		if (TOS_NODE_ID == 0) {

			// add some color to your life
			dbg("SRTreeC","%s\n",KCYN);
			dbg("SRTreeC", "######################################################################################## \n");
			dbg("SRTreeC", "################################   Initialize Routing   ################################ \n");
			dbg("SRTreeC", "########################################################################################%s\n",KNRM);
			dbg("SRTreeC","\n");
		}


		if (call RoutingSendQueue.full()) {
			dbg("Routing", "RoutingMsgTimer.fired(): %sRouting Send Q Full... %s\n",KRED,KNRM);
			return;
		}

		// Make a routing package 
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if (mrpkt == NULL) {
			dbg("Routing", "RoutingMsgTimer.fired(): %sNo valid payload... %s\n",KRED,KNRM);
			return;
		}

		// Calculate Query
		query = query2 << 4;
		query = query | query1;
		dbg("Routing" , "RoutingMsgTimer.fired(): Calculated Query = %d\n",query);

		// Fill package
		atomic {
			mrpkt->senderID = TOS_NODE_ID;
			mrpkt->depth = curdepth;
			mrpkt->query = query;
		}

		// Send Routing Package
		dbg("Routing" , "RoutingMsgTimer.fired(): Sending RoutingMsg... \n");

		//Set Destination Addr
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		//Set Payload length
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		//Add msg to RoutingMSG Queue
		enqueueDone = call RoutingSendQueue.enqueue(tmp);
		//Check if packet enqueued successfully 
		if (enqueueDone == SUCCESS) {
			dbg("Routing", "RoutingMsgTimer.fired(): %sRoutingMsg enqueued successfully in SendingQueue!!!%s\n",KGRN,KNRM);
			if (call RoutingSendQueue.size() == 1) {
				dbg("Routing", "RoutingMsgTimer.fired(): %sSendTask() posted!!%s\n",KGRN,KNRM);
				post sendRoutingTask();
			}
			// TODO: What is this ?!?
			else{
				dbg("Routing", "RoutingMsgTimer.fired(): %sRouting Queue != 1 %s\n",KRED,KNRM);
			}
		} else {
			dbg("Routing", "RoutingMsgTimer.fired(): %sRoutingMsg failed to be enqueued in SendingQueue!!!%s\n",KRED,KNRM);
		}

		//calculate subquerys(for self)
		post calculateSubQ();

		//Start your epoch
		post startEpoch();
	}

	// Timer for epoch periods
	event void EpochTimer.fired() {
		uint32_t rand_off;
		uint32_t measurement;

		epochCounter++ ;
		dbg("Timing", "EpochTimer.fired(): %s######################################################## EPOCH %d %s\n",KCYN,epochCounter,KNRM);

		//random offset granularity (how many possible sub-slots)
		#define granularity 50

		// Calculate a small random offset 
		rand_off = (call RandomGenerator.rand32() % granularity)*((EPOCH_PERIOD_MILLI/MAX_DEPTH)/granularity);
		// dbg("Timing", "EpochTimer.fired(): offset_milli+rand_off = %d \n",offset_milli+rand_off);


		//Restart Timer
		call EpochTimer.startOneShot(EPOCH_PERIOD_MILLI);
		//(Re)start Slot Timer
		call SlotTimer.startOneShot(offset_milli-rand_off);

		//Produce new Measurement
		measurement = call RandomGenerator.rand16() % 50;
		dbg("Measure", "EpochTimer.fired(): %sMeasured %d %s\n",KMAG,measurement,KNRM);

		//initialize internal values
		initCdm();
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

		dbg("NotifyParentMsg", "NotifyReceive.receive(): Something received!!!  from %u - Original source %u \n", ((NotifyParentMsg*) payload)->senderID, msource);

		//if(len!=sizeof(NotifyParentMsg))
		//{
		//dbg("SRTreeC","\t\tUnknown message received!!!\n");
		//return msg;http://courses.ece.tuc.gr/
		//}

		atomic {
			memcpy(&tmp, msg, sizeof(message_t));
			//tmp=*(message_t*)msg;
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

		dbg("Routing", "RoutingReceive.receive(): Something received!!!  from %u - Original source %u \n", ((RoutingMsg*) payload)->senderID ,  msource);

		if(len!=sizeof(RoutingMsg))
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

	//////////////////////////////////// Tasks implementations /////////////////////////////////

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
			setLostRoutingSendTask(TRUE);
			return;
		}

		radioRoutingSendPkt = call RoutingSendQueue.dequeue();

		mlen = call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest = call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if (mlen != sizeof(RoutingMsg)) {
			dbg("Routing", "sendRoutingTask(): %sUnknown message%s\n",KRED,KNRM);
			return;
		}

		//Mutex
		setRoutingSendBusy(TRUE);
		sendDone = call RoutingAMSend.send(mdest, &radioRoutingSendPkt, mlen);

		if ( sendDone != SUCCESS) {
			setRoutingSendBusy(FALSE);
		}

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
			setLostNotifySendTask(TRUE);
			return;
		}

		//dequeue packet
		radioNotifySendPkt = call NotifySendQueue.dequeue();

		//get payload length
		mlen = call NotifyPacket.payloadLength(&radioNotifySendPkt);

		//get payload
		mpayload = call NotifyPacket.getPayload(&radioNotifySendPkt, mlen);

		// check if message is known
		if (mlen != ms[numOfSubQ-1]) {
			dbg("SRTreeC", "\t\t sendNotifyTask(): Unknown message!!\n");
			return;
		}

		dbg("SRTreeC" , "sendNotifyTask(): mlen = %u  senderID= %u \n", mlen, getSenderID(mpayload));
		mdest = call NotifyAMPacket.destination(&radioNotifySendPkt);

		//send notification packet
		sendDone = call NotifyAMSend.send(mdest, &radioNotifySendPkt, mlen);

		if ( sendDone == SUCCESS) {
			dbg("SRTreeC", "sendNotifyTask(): %sSend Success!!!%s\n",KGRN,KNRM);
		} else {
			dbg("SRTreeC", "sendNotifyTask(): %sSend Failed!!!%s\n",KRED,KNRM);
			//TODO: 
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

		// Dequeues the message
		radioRoutingRecPkt = call RoutingReceiveQueue.dequeue();
		// Length of message (?!?)
		len = call RoutingPacket.payloadLength(&radioRoutingRecPkt);

		dbg("Routing", "ReceiveRoutingTask(): Function called with packet length =%u \n", len);
		
		// Processing Radio Packet
		if (len == sizeof(RoutingMsg)) {
			
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt, len));

			dbg("Routing" , "receiveRoutingTask(): Routing Message Packet -> senderID= %d , senderDepth= %d , size= %d \n",mpkt->senderID , mpkt->depth,sizeof(mpkt));
			// Check if NODE is orphan
			if ( (parentID < 0) || (parentID >= 65535)) {
				// Sender is the parent
				parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
				// Calculate current depth
				curdepth = mpkt->depth + 1;
				// Calculate Querys
				query1= (mpkt->query) & 15;
				query2= (mpkt->query) >> 4;
				// Calculate SubQuerys
				post calculateSubQ();
				dbg("Routing" , "receiveRoutingTask(): %sNode routed -> Parent = %d, Depth = %d, Query1 = %d, Query2 = %d%s\n",KBLU, parentID, curdepth, query1, query2, KNRM);
				dbg("Query" , "receiveRoutingTask(): %sQuery Requests Received: Query1 = %d, Query2 = %d%s\n",KBLU, query1, query2, KNRM);
				// Route your children
				dbg("Routing", "receiveRoutingTask(): Call RoutingMsgTimer to route children%s\n",KNRM);
				if (TOS_NODE_ID != 0) {
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
			}

		} else {
			dbg("Routing", "receiveRoutingTask(): %sEmpty message%s\n",KRED,KNRM);
			setLostRoutingRecTask(TRUE);
			return;
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

		//dequeue message
		radioNotifyRecPkt = call NotifyReceiveQueue.dequeue();

		len = call NotifyPacket.payloadLength(&radioNotifyRecPkt);

		dbg("NotifyParentMsg", "ReceiveNotifyTask(): len=%u \n", len);
		// check if packet is correct
		if (len == ms[numOfSubQ-1]) {
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt, len));

			dbg("NotifyParentMsg" , "NotifyParentMsg received from %d !!! \n", mr->senderID);
			// If packet is for me
			if ( mr->parentID == TOS_NODE_ID) {

				//UPDATE DataQueue -------------------------------------------------------------------------------------
				//Get Message Sender ID
				SID = mr->senderID;

				// Search for that sender in DataQueue
				for(i=0;i< call DataQueue.size();i++){
					tmp = call DataQueue.dequeue();

					len = call NotifyPacket.payloadLength(&tmp);
					mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&tmp, len));

					//If message isnt from the same sender
					if(mr->senderID != SID){
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
			dbg("NotifyParentMsg", "receiveNotifyTask():%sEmpty message!!!%s \n",KRED,KNRM);
			setLostNotifyRecTask(TRUE);
			return;
		}
	}

    // Start The Epoch
	task void startEpoch(){
		message_t tmp;
		//Start Epoch Timer
		call EpochTimer.startOneShot(TIMER_FAST_PERIOD);
		//Calculate offset milli (for sending measurements)
		offset_milli = EPOCH_PERIOD_MILLI / MAX_DEPTH;
		offset_milli = offset_milli*(MAX_DEPTH - curdepth);

		dbg("Timing", "startEpoch(): %sStarted Epoch Timer. Offset Milli = %d%s\n",KCYN,offset_milli, KNRM);
	}

	// Aggregates data from DataQueue
	task void calculateData(){
		uint8_t len;
		uint8_t i;
		message_t tmp;
		void* mr;

		// Iterate Data Queue
		for(i=0;i< call DataQueue.size();i++){
			//dequeue
			tmp = call DataQueue.dequeue();

			//get payload
			len = call NotifyPacket.payloadLength(&tmp);
			mr = call NotifyPacket.getPayload(&tmp, len);

			//unpack data
			//TODO: UNPACK DATA

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
		
		void* m;
		int len;

		m = call NotifyPacket.getPayload(&tmp,ms[numOfSubQ-1]); 
		
		// Populate message
		setSenderID(m,TOS_NODE_ID);
		setDepth(m,curdepth);
		setParentID(m,parentID);
		pack(getNumPtr(m),cdm);

		

		// call NotifyAMPacket.setDestination(&tmp, parentID);
		// call NotifyAMPacket.setType(&tmp,AM_NOTIFYPARENTMSG);
		// call NotifyPacket.setPayloadLength(&tmp, ms[numOfSubQ-1]);

		// // Enqueue packet to be sent
		// if (call NotifySendQueue.enqueue(tmp) == SUCCESS) {
		// 	dbg("NotifyParentMsg", "enqueueData(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
		// 	if (call NotifySendQueue.size() == 1) {
		// 		// send the packet
		// 		post sendNotifyTask();
		// 	}
		// }
	}

	// Makes final calculations and presents root data
	task void rootResults(){
 
		dbg("Root", "\n");
		dbg("Root", "rootResults(): %s################################################### ROOT RESULTS FOR EPOCH %d ###################################################s\n",KBLU,epochCounter,KNRM);
		//dbg("Root", "rootResults(): %s############  SUM   : %s%d %s\n",KBLU,KMAG,SUM ,KNRM);
		//dbg("Root", "rootResults(): %s############  COUNT : %s%d %s\n",KBLU,KMAG,COUNT ,KNRM);
		//dbg("Root", "rootResults(): %s############  AVG   : %s%d %s\n",KBLU,KMAG,AVG ,KNRM);
		//dbg("Root", "rootResults(): %s############  MAX   : %s%d %s\n\n",KBLU,KMAG,MAX ,KNRM);
	}

	// Calculates SubQuerys number from query1 and query2
	task void calculateSubQ(){
		uint8_t i;

		// calculate subquerys
		if (query1 > 6 || query2 > 6){
			dbg("Query", "calculateSubQ(): %sUnknown Query %s\n",KRED,KNRM);
			return;
		}

		subquerys = subquerys | qem[query1-1];
		subquerys = subquerys | qem[query2-1];

		// calculate number of subquery values
		for(i=0;i<5;i++){
			if(((subquerys >> i)&1) == 1){numOfSubQ++;}
		}

		dbg("Query", "calculateSubQ(): Calculcated subquerys= %d, numOfSubQ=%d\n",subquerys,numOfSubQ);
	}


}
