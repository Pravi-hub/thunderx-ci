/*
 *  TCI relay.
 */

/*
 * Message formats:
 *  'CKI:<token>'		= Check in resource.
 *  'CKO:<resource>:<seconds>'	= Check out resource.
 *  'CKQ:<resource>'		= Check out query.
 *  'DMP:all'			= Admin - Dump all lists.
 *  'GET:<token>'		= Get relay info.
 *  'PUT:<token>:<server>'	= Put relay info.
 *
 * GET Replies:
 *  'ERR:<type={TODO}>'		= Error in incoming message.
 *  'OK-:<server>'		= Message delivered.
 *
 * PUT Replies:
 *  'ERR:<type={TODO}>'		= Error in incoming message.
 *  'FWD'			= Forwarded to waiting master.
 *  'QED'			= Queued to list.
 *  'UPD'			= Duplicate, list updated.
 *
 * CKI Replies:
 *  'ERR:<type={TODO}>'		= Error in incoming message.
 *  'OK-:<token>'		= Checkin success.
 *
 * CKO Replies:
 *  'ERR:<type={TODO}>'		= Error in incoming message.
 *  'OK-:<token>'		= Checkout success.
 */

#define msg_data_len 64
#define msg_buffer_len 128

