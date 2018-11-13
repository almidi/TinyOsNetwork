#include "SimpleRoutingTree.h"

module SRTreeC

#define KNRM  "\x1B[0m"
#define KRED  "\x1B[31m"
#define KGRN  "\x1B[32m"
#define KYEL  "\x1B[33m"
#define KBLU  "\x1B[34m"
#define KMAG  "\x1B[35m"
#define KCYN  "\x1B[36m"
#define KWHT  "\x1B[37m"

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

	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;

	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;

	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;
}

//Implement Network

implementation {
	// Epochs
	uint16_t  roundCounter;

	// Def Message Types
	// Messages for routing the network
	message_t radioRoutingSendPkt;
	message_t radioNotifySendPkt;

	bool RoutingSendBusy = FALSE;
	bool NotifySendBusy = FALSE;
	bool lostRoutingSendTask = FALSE;
	bool lostNotifySendTask = FALSE;
	bool lostRoutingRecTask = FALSE;
	bool lostNotifyRecTask = FALSE;

	uint8_t curdepth;
	uint16_t parentID;

	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();

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

	// Boot of device
	event void Boot.booted() {
		// Start Radio
		call RadioControl.start();

		//epoch counter
		roundCounter = 0;

		// If Root Node
		if (TOS_NODE_ID == 0) {
			// Root Node = 0 Depth
			curdepth = 0;
			parentID = 0;
		} else {
			//-1 = Undefined Depth (will be calculated later)
			curdepth = -1;
			parentID = -1;		
		}
		dbg("Boot", "%sNode Booted:%s curdepth = %03d  ,  parentID= %d\n",KYEL, KNRM, curdepth , parentID);
	}

	// Radio Started
	event void RadioControl.startDone(error_t err) {
		if (err == SUCCESS) {
			dbg("Radio" , "RadioControl.StartDone():%s Radio initialized successfully!!!%s\n",KYEL,KNRM);

			//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//call RoutingMsgTimer.startPeriodic(TIMER_PERIOD_MILLI);
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
		dbg("Radio", "%sRadioControl.stopDone(): Radio stopped!%s\n",KYEL,KNRM);	
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

		RoutingMsg* mrpkt;
		dbg("Routing", "RoutingMsgTimer fired! -----------------------------------------------------------------\n");
		dbg("Routing", "RoutingMsgTimer.fired(): radioBusy = %s %s\n", (RoutingSendBusy) ? "\x1B[31mTrue" : "\x1B[32mFalse",KNRM);
		
		if (TOS_NODE_ID == 0) {
			roundCounter += 1;

			// add some color to your life
			dbg("SRTreeC","%s\n",KCYN);
			dbg("SRTreeC", "######################################################################################## \n");
			dbg("SRTreeC", "###################################   ROUND   %03u    ################################### \n", roundCounter);
			dbg("SRTreeC", "########################################################################################%s\n",KNRM);
			dbg("SRTreeC","\n");

			// call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
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

		// Fill package
		atomic {
			mrpkt->senderID = TOS_NODE_ID;
			mrpkt->depth = curdepth;
		}

		// Send Routing Package
		dbg("Routing" , "RoutingMsgTimer.fired(): Sending RoutingMsg... \n");

		//Set Destination Addr
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		//Set Payload length
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		//Add msg to RoutingMSG Queue
		enqueueDone = call RoutingSendQueue.enqueue(tmp);
		//Check if pachet enqueued successfully 
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

		//if(len!=sizeof(RoutingMsg))
		//{
		//dbg("SRTreeC","\t\tUnknown message received!!!\n");
		//return msg;
		//}

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

	////////////// Tasks implementations //////////////////////////////
	// dequeues a routing message and sends it
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

		//Check Mutext
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

	// dequeues a notification message and sends it
	task void sendNotifyTask() {
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;
		NotifyParentMsg* mpayload;

		//message_t radioNotifySendPkt;

		if (call NotifySendQueue.empty()) {
			dbg("SRTreeC", "sendNotifyTask(): Q is empty!\n");
			return;
		}

		if (NotifySendBusy == TRUE) {
			dbg("SRTreeC", "sendNotifyTask(): NotifySendBusy= TRUE!!!\n");
			setLostNotifySendTask(TRUE);
			return;
		}

		radioNotifySendPkt = call NotifySendQueue.dequeue();

		mlen = call NotifyPacket.payloadLength(&radioNotifySendPkt);

		mpayload = call NotifyPacket.getPayload(&radioNotifySendPkt, mlen);

		if (mlen != sizeof(NotifyParentMsg)) {
			dbg("SRTreeC", "\t\t sendNotifyTask(): Unknown message!!\n");
			return;
		}

		dbg("SRTreeC" , "sendNotifyTask(): mlen = %u  senderID= %u \n", mlen, mpayload->senderID);
		mdest = call NotifyAMPacket.destination(&radioNotifySendPkt);


		sendDone = call NotifyAMSend.send(mdest, &radioNotifySendPkt, mlen);

		if ( sendDone == SUCCESS) {
			dbg("Routing", "sendNotifyTask(): %sSend Success!!!%s\n",KGRN,KNRM);
		} else {
			dbg("Routing", "sendNotifyTask(): %sSend Failed!!!%s\n",KRED,KNRM);
			setNotifySendBusy(FALSE);
		}
	}

	// dequeues a routing message and processes it
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
			

			NotifyParentMsg* m;
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt, len));

			dbg("Routing" , "receiveRoutingTask(): Routing Message Packet -> senderID= %d , senderDepth= %d \n",mpkt->senderID , mpkt->depth);
			// Check if NODE is orphan
			if ( (parentID < 0) || (parentID >= 65535)) {
				// Sender is the parent
				parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
				// Calculate current depth
				curdepth = mpkt->depth + 1;

				dbg("Routing" , "receiveRoutingTask(): %sNode routed -> Parent = %d, Depth = %d%s\n",KBLU, parentID, curdepth, KNRM);

				// Notify the parent about your adoption
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				m->senderID = TOS_NODE_ID;
				m->depth = curdepth;
				m->parentID = parentID;
				dbg("Routing" , "receiveRoutingTask():NotifyParentMsg sending to node= %d... \n", parentID);
				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp, sizeof(NotifyParentMsg));

				//Enqueue message
				enqueueDone = call NotifySendQueue.enqueue(tmp);
				dbg("Routing", "receiveRoutingTask(): NotifyParentMsg enqueue %s%s\n",(enqueueDone == SUCCESS) ? "\x1B[32mSuccessful" : "\x1B[31mFailed",KNRM);
 				if (enqueueDone == SUCCESS && call NotifySendQueue.size() == 1) {
					post sendNotifyTask();
				}

				// Route your childs
				dbg("Routing", "receiveRoutingTask(): Call RoutingMsgTimer to route childs%s\n",KNRM);
				if (TOS_NODE_ID != 0) {
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}

			// If Node Not orphan see if new parent is better (closer, with more money, etc.)
			}else if(curdepth > mpkt->depth + 1){
				dbg("Routing" , "receiveRoutingTask(): %sFound Better Parent%s\n" ,KBLU ,KNRM);
				oldparentID = parentID;

				// Sender is the parent
				parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
				// Calculate current depth
				curdepth = mpkt->depth + 1;

				dbg("Routing" , "receiveRoutingTask(): %sNode rerouted -> Parent = %d, Depth = %d%s\n",KBLU, parentID, curdepth, KNRM);

				// Notify New Parent About his adoption
				dbg("Routing" , "receiveRoutingTask(): NotifyParentMsg sending to node= %d... \n", oldparentID);
				if ( (oldparentID < 65535) || (oldparentID > 0) || (oldparentID == parentID)) {
					m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
					m->senderID = TOS_NODE_ID;
					m->depth = curdepth;
					m->parentID = parentID;

					call NotifyAMPacket.setDestination(&tmp, oldparentID);
					//call NotifyAMPacket.setType(&tmp,AM_NOTIFYPARENTMSG);
					call NotifyPacket.setPayloadLength(&tmp, sizeof(NotifyParentMsg));

					if (call NotifySendQueue.enqueue(tmp) == SUCCESS) {
						dbg("Routing", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
						if (call NotifySendQueue.size() == 1) {
							post sendNotifyTask();
						}
					}
				}

				// Notify Old Parent About your change
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				m->senderID = TOS_NODE_ID;
				m->depth = curdepth;
				m->parentID = parentID;
				dbg("Routing" , "receiveRoutingTask(): NotifyParentMsg sending to node= %d... \n", parentID);
				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp, sizeof(NotifyParentMsg));

				if (call NotifySendQueue.enqueue(tmp) == SUCCESS) {
					dbg("Routing", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!! \n");
					if (call NotifySendQueue.size() == 1) {
						post sendNotifyTask();
					}
				}

				// Reroute your childs
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
		message_t tmp;
		uint8_t len;
		message_t radioNotifyRecPkt;

		radioNotifyRecPkt = call NotifyReceiveQueue.dequeue();

		len = call NotifyPacket.payloadLength(&radioNotifyRecPkt);

		dbg("SRTreeC", "ReceiveNotifyTask(): len=%u \n", len);
		if (len == sizeof(NotifyParentMsg)) {
			// an to parentID== TOS_NODE_ID tote
			// tha proothei to minima pros tin riza xoris broadcast
			// kai tha ananeonei ton tyxon pinaka paidion..
			// allios tha diagrafei to paidi apo ton pinaka paidion

			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt, len));

			dbg("SRTreeC" , "NotifyParentMsg received from %d !!! \n", mr->senderID);
			if ( mr->parentID == TOS_NODE_ID) {
				// tote prosthiki stin lista ton paidion.

			} else {
				// apla diagrafei ton komvo apo paidi tou..

			}
			if ( TOS_NODE_ID == 0) {

			} else {
				NotifyParentMsg* m;
				memcpy(&tmp, &radioNotifyRecPkt, sizeof(message_t));

				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				//m->senderID=mr->senderID;
				//m->depth = mr->depth;
				//m->parentID = mr->parentID;

				dbg("SRTreeC" , "Forwarding NotifyParentMsg from senderID= %d  to parentID=%d \n" , m->senderID, parentID);
				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp, sizeof(NotifyParentMsg));

				if (call NotifySendQueue.enqueue(tmp) == SUCCESS) {
					dbg("SRTreeC", "receiveNotifyTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
					if (call NotifySendQueue.size() == 1) {
						post sendNotifyTask();
					}
				}

			}

		} else {
			dbg("SRTreeC", "receiveNotifyTask():Empty message!!! \n");
			setLostNotifyRecTask(TRUE);
			return;
		}

	}
}
